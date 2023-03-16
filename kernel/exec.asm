;===============================================================================
;Copyright (C) Andrzej Adamczyk (at https://blackdev.org/). All rights reserved.
;===============================================================================

;-------------------------------------------------------------------------------
; in:
;	rcx - length of string in characters
;	rsi - pointer to string
;	rdi - stream flags
;	rbp - pointer to exec descriptor
; out:
;	rax - new process ID
kernel_exec:
	; preserve original registers
	push	rbx
	push	rcx
	push	rdx
	push	rsi
	push	rdi
	push	rbp
	push	r8
	push	r9
	push	r10
	push	r11
	push	r13
	push	r14

	; kernel environment variables/rountines base address
	mov	r8,	qword [kernel_environment_base_address]

	; select file name from string
	mov	al,	STATIC_ASCII_SPACE
	call	lib_string_word

	; by default there is no PID for new process
	xor	eax,	eax

	;-----------------------------------------------------------------------
	; locate and load file into memory
	;-----------------------------------------------------------------------

	; file descriptor
	mov	rcx,	rbx
	sub	rsp,	KERNEL_STORAGE_STRUCTURE_FILE.SIZE
	mov	rbp,	rsp	; pointer of file descriptor
	call	kernel_exec_load

	; file loaded?
	cmp	qword [rbp + KERNEL_STORAGE_STRUCTURE_FILE.id],	EMPTY
	je	.end	; no

	; load depended libraries
	mov	r13,	qword [rbp + KERNEL_STORAGE_STRUCTURE_FILE.address]
	call	kernel_library_import

	;-----------------------------------------------------------------------
	; configure executable
	;-----------------------------------------------------------------------

	; orignal name/path length
	mov	rcx,	qword [rsp + KERNEL_STORAGE_STRUCTURE_FILE.SIZE + 0x50]
	call	kernel_exec_configure

	;-----------------------------------------------------------------------
	; connect libraries to file executable (if needed)
	;-----------------------------------------------------------------------
	call	kernel_exec_link

	;-----------------------------------------------------------------------
	; standard input/output (stream)
	;-----------------------------------------------------------------------

	; retrieve stream flow
	mov	rax,	qword [rsp + KERNEL_STORAGE_STRUCTURE_FILE.SIZE + 0x38]

	; prepare default input stream
	call	kernel_stream
	mov	qword [r10 + KERNEL_TASK_STRUCTURE.stream_in],	rsi

	; connect output with input?
	test	rax,	LIB_SYS_STREAM_FLOW_out_to_in
	jnz	.stream_set	; yes

.no_loop:
	; properties of parent task
	call	kernel_task_active

	; connect output to parents input?
	test	rax,	LIB_SYS_STREAM_FLOW_out_to_parent_in
	jz	.no_input	; no

	; redirect output to parents input
	mov	rsi,	qword [r9 + KERNEL_TASK_STRUCTURE.stream_in]

	; stream configured
	jmp	.stream_set

.no_input:
	; default configuration
	mov	rsi,	qword [r9 + KERNEL_TASK_STRUCTURE.stream_out]

.stream_set:
	; update stream output of child
	mov	qword [r10 + KERNEL_TASK_STRUCTURE.stream_out],	rsi

	; increase stream usage
	inc	qword [rsi + KERNEL_STREAM_STRUCTURE.count]

	;-----------------------------------------------------------------------
	; new process initialized
	;-----------------------------------------------------------------------

	; mark task as ready
	or	word [r10 + KERNEL_TASK_STRUCTURE.flags],	KERNEL_TASK_FLAG_active | KERNEL_TASK_FLAG_init

	; release file content
	mov	rsi,	qword [rsp + KERNEL_STORAGE_STRUCTURE_FILE.size_byte]
	add	rsi,	~STATIC_PAGE_mask
	shr	rsi,	STATIC_PAGE_SIZE_shift
	mov	rdi,	qword [rsp + KERNEL_STORAGE_STRUCTURE_FILE.address]
	call	kernel_memory_release

	; return task ID
	mov	rax,	qword [r10 + KERNEL_TASK_STRUCTURE.pid]

.end:
	; remove file descriptor from stack
	add	rsp,	KERNEL_STORAGE_STRUCTURE_FILE.SIZE

	; restore original registers
	pop	r14
	pop	r13
	pop	r11
	pop	r10
	pop	r9
	pop	r8
	pop	rbp
	pop	rdi
	pop	rsi
	pop	rdx
	pop	rcx
	pop	rbx

	; return from routine
	ret

;-------------------------------------------------------------------------------
; in:
;	rcx - length of path
;	rsi - pointer to path
;	r13 - pointer to file content
; out:
;	rdi - pointer to executable space
;	r10 - pointer to task entry
kernel_exec_configure:
	; preserve original registers
	push	rax
	push	rbx
	push	rcx
	push	rdx
	push	rsi
	push	rbp
	push	r8
	push	r9
	push	r11
	push	r12
	push	r13
	push	r14
	push	r15

	;-----------------------------------------------------------------------
	; prepare task for execution
	;-----------------------------------------------------------------------

	; register new task on queue
	call	kernel_task_add

	;-----------------------------------------------------------------------
	; paging array of new process
	;-----------------------------------------------------------------------

	; make space for the process paging table
	call	kernel_memory_alloc_page

	; update task entry about paging array
	mov	qword [r10 + KERNEL_TASK_STRUCTURE.cr3],	rdi

	;-----------------------------------------------------------------------
	; context stack and return point (initialization entry)
	;-----------------------------------------------------------------------

	; describe the space under context stack of process
	mov	rax,	KERNEL_TASK_STACK_address
	mov	bx,	KERNEL_PAGE_FLAG_present | KERNEL_PAGE_FLAG_write | KERNEL_PAGE_FLAG_process
	mov	ecx,	KERNEL_TASK_STACK_SIZE_page
	mov	r11,	rdi
	call	kernel_page_alloc

	; set process context stack pointer
	mov	qword [r10 + KERNEL_TASK_STRUCTURE.rsp],	KERNEL_TASK_STACK_pointer - (KERNEL_EXEC_STRUCTURE_RETURN.SIZE + KERNEL_EXEC_STACK_OFFSET_registers)

	; prepare exception exit mode on context stack of process
	mov	rsi,	KERNEL_TASK_STACK_pointer - STATIC_PAGE_SIZE_byte
	call	kernel_page_address

	; set pointer to return descriptor
	add	rax,	qword [kernel_page_mirror]	; convert to logical address
	add	rax,	STATIC_PAGE_SIZE_byte - KERNEL_EXEC_STRUCTURE_RETURN.SIZE

	; set first instruction executed by process
	mov	rdx,	qword [r13 + LIB_ELF_STRUCTURE.program_entry_position]
	mov	qword [rax + KERNEL_EXEC_STRUCTURE_RETURN.rip],	rdx

	; code descriptor
	mov	qword [rax + KERNEL_EXEC_STRUCTURE_RETURN.cs],	KERNEL_GDT_STRUCTURE.cs_ring3 | 0x03

	; default processor state flags
	mov	qword [rax + KERNEL_EXEC_STRUCTURE_RETURN.eflags],	KERNEL_TASK_EFLAGS_default

	; default stack pointer
	mov	rdx,	KERNEL_EXEC_STACK_pointer
	mov	qword [rax + KERNEL_EXEC_STRUCTURE_RETURN.rsp],	rdx

	; stack descriptor
	mov	qword [rax + KERNEL_EXEC_STRUCTURE_RETURN.ss],	KERNEL_GDT_STRUCTURE.ds_ring3 | 0x03

	;-----------------------------------------------------------------------
	; stack
	;-----------------------------------------------------------------------

	; describe the space under process stack
	mov	rax,	KERNEL_EXEC_STACK_address
	or	bx,	KERNEL_PAGE_FLAG_user
	mov	ecx,	KERNEL_EXEC_STACK_SIZE_page
	call	kernel_page_alloc

	;-----------------------------------------------------------------------
	; allocate space for executable segments
	;-----------------------------------------------------------------------

	; size of unpacked executable
	call	kernel_exec_size

	; convert limit address to offset
	sub	rcx,	KERNEL_EXEC_BASE_address

	; assign memory space for executable
	add	rcx,	~STATIC_PAGE_mask
	shr	rcx,	STATIC_PAGE_SIZE_shift
	call	kernel_memory_alloc

	; preserve executable location and size in Pages
	push	rdi
	push	rcx

	; map executable space to process paging array
	mov	eax,	KERNEL_EXEC_BASE_address
	mov	rsi,	rdi
	sub	rsi,	qword [kernel_page_mirror]
	call	kernel_page_map

	;-----------------------------------------------------------------------
	; load program segments in place
	;-----------------------------------------------------------------------

	; number of program headers
	movzx	ecx,	word [r13 + LIB_ELF_STRUCTURE.header_entry_count]

	; beginning of header section
	mov	rdx,	qword [r13 + LIB_ELF_STRUCTURE.header_table_position]
	add	rdx,	r13

.elf_header:
	; ignore empty headers
	cmp	dword [rdx + LIB_ELF_STRUCTURE_HEADER.type],	EMPTY
	je	.elf_header_next	; empty one
	cmp	qword [rdx + LIB_ELF_STRUCTURE_HEADER.memory_size],	EMPTY
	je	.elf_header_next	; this too

	; load segment?
	cmp	dword [rdx + LIB_ELF_STRUCTURE_HEADER.type],	LIB_ELF_HEADER_TYPE_load
	jne	.elf_header_next	; no

	; preserve original registers
	push	rcx
	push	rdi

	; segment destination
	add	rdi,	qword [rdx + LIB_ELF_STRUCTURE_HEADER.virtual_address]
	sub	rdi,	KERNEL_EXEC_BASE_address

	; segment source
	mov	rsi,	r13
	add	rsi,	qword [rdx + LIB_ELF_STRUCTURE_HEADER.segment_offset]

	; copy segment in place
	mov	rcx,	qword [rdx + LIB_ELF_STRUCTURE_HEADER.segment_size]
	rep	movsb

	; restore original registers
	pop	rdi
	pop	rcx

.elf_header_next:
	; move pointer to next entry
	add	rdx,	LIB_ELF_STRUCTURE_HEADER.SIZE

	; end of hedaer table?
	dec	rcx
	jnz	.elf_header	; no

	;-----------------------------------------------------------------------
	; virtual memory map
	;-----------------------------------------------------------------------

	; assign memory space for binary memory map with same size as kernels
	mov	rcx,	qword [r8 + KERNEL_STRUCTURE.page_limit]
	shr	rcx,	STATIC_DIVIDE_BY_8_shift	; 8 pages per Byte
	add	rcx,	~STATIC_PAGE_mask	; align up to page boundaries
	shr	rcx,	STATIC_PAGE_SIZE_shift	; convert to pages
	call	kernel_memory_alloc

	; store binary memory map address of process inside task properties
	mov	qword [r10 + KERNEL_TASK_STRUCTURE.memory_map],	rdi

	; preserve binary memory map location
	push	rdi

	; fill memory map with available pages
	mov	eax,	STATIC_MAX_unsigned
	mov	rcx,	qword [r8 + KERNEL_STRUCTURE.page_limit]
	shr	rcx,	STATIC_DIVIDE_BY_32_shift	; 32 pages per chunk

	; first 1 MiB is reserved for future devices mapping
	sub	rcx,	(KERNEL_EXEC_BASE_address >> STATIC_PAGE_SIZE_shift) >> STATIC_DIVIDE_BY_32_shift
	add	rdi,	(KERNEL_EXEC_BASE_address >> STATIC_PAGE_SIZE_shift) >> STATIC_DIVIDE_BY_8_shift

	; proceed
	rep	stosd

	; restore memory map location and executable space size in Pages
	pop	rsi
	pop	rcx

	; mark first N bytes of executable space as reserved
	mov	r9,	rsi
	call	kernel_memory_acquire

	;-----------------------------------------------------------------------
	; kernel environment
	;-----------------------------------------------------------------------

	; map kernel space to process
	call	kernel_page_merge

	; restore executable space address
	pop	rdi

	; restore original registers
	pop	r15
	pop	r14
	pop	r13
	pop	r12
	pop	r11
	pop	r9
	pop	r8
	pop	rbp
	pop	rsi
	pop	rdx
	pop	rcx
	pop	rbx
	pop	rax

	; return from routine
	ret

;-------------------------------------------------------------------------------
; in:
;	rdi - pointer to logical executable space
;	r13 - pointer to file content
kernel_exec_link:
	; preserve original registers
	push	rax
	push	rbx
	push	rcx
	push	rdx
	push	rsi
	push	r8
	push	r9
	push	r10
	push	r11
	push	r12
	push	r13

	; we need to find 4 header locations to be able to resolve bindings to functions

	; number of entries in header table
	movzx	ecx,	word [r13 + LIB_ELF_STRUCTURE.section_entry_count]

	; set pointer to begining of header table
	add	r13,	qword [r13 + LIB_ELF_STRUCTURE.section_table_position]

	; reset section locations
	xor	r8,	r8
	xor	r9,	r9
	xor	r10,	r10
	xor	r11,	r11

.section:
	; program data?
	cmp	dword [r13 + LIB_ELF_STRUCTURE_SECTION.type],	LIB_ELF_SECTION_TYPE_progbits
	jne	.no_program_data	; no

	; set pointer to program data
	mov	r11,	qword [r13 + LIB_ELF_STRUCTURE_SECTION.virtual_address]
	sub	r11,	KERNEL_EXEC_BASE_address
	add	r11,	rdi

.no_program_data:
	; string table?
	cmp	dword [r13 + LIB_ELF_STRUCTURE_SECTION.type],	LIB_ELF_SECTION_TYPE_strtab
	jne	.no_string_table	;no

	; first only
	test	r10,	r10
	jnz	.no_string_table

	; set pointer to string table
	mov	r10,	qword [r13 + LIB_ELF_STRUCTURE_SECTION.file_offset]
	add	r10,	qword [rsp]

.no_string_table:
	; dynamic relocation?
	cmp	dword [r13 + LIB_ELF_STRUCTURE_SECTION.type],	LIB_ELF_SECTION_TYPE_rela
	jne	.no_dynamic_relocation	; no

	; set pointer to dynamic relocation
	mov	r8,	qword [r13 + LIB_ELF_STRUCTURE_SECTION.file_offset]
	add	r8,	qword [rsp]

	; and size on Bytes
	mov	rbx,	qword [r13 + LIB_ELF_STRUCTURE_SECTION.size_byte]

.no_dynamic_relocation:
	; dynamic symbols?
	cmp	dword [r13 + LIB_ELF_STRUCTURE_SECTION.type],	LIB_ELF_SECTION_TYPE_dynsym
	jne	.no_dynamic_symbols	; no

	; set pointer to dynamic symbols
	mov	r9,	qword [r13 + LIB_ELF_STRUCTURE_SECTION.file_offset]
	add	r9,	qword [rsp]

.no_dynamic_symbols:
	; move pointer to next entry
	add	r13,	LIB_ELF_STRUCTURE_SECTION.SIZE

	; end of section header?
	loop	.section	; no

	;---

	; if dynamic relocations doesn't exist
	test	r8,	r8
	jz	.end	; executable doesn't need external functions

	; move pointer to first function address entry
	add	r11,	0x18

	; function index inside Global Offset Table
	xor	r12,	r12

.function:
	; or symbolic value exist
	cmp	qword [r8 + LIB_ELF_STRUCTURE_DYNAMIC_RELOCATION.symbol_value],	EMPTY
	jne	.function_next

	; get function index
	mov	eax,	dword [r8 + LIB_ELF_STRUCTURE_DYNAMIC_RELOCATION.index]

	; calculate offset to function name
	mov	rcx,	LIB_ELF_STRUCTURE_DYNAMIC_SYMBOL.SIZE
	mul	rcx

; software is not relocatable yet, so for now we don't use this piece of code

; 	; it's a local function?
; 	cmp	qword [r9 + rax + LIB_ELF_STRUCTURE_DYNAMIC_SYMBOL.address],	EMPTY
; 	je	.function_global	; no

; 	; retrieve local function correct address
; 	mov	rsi,	qword [r9 + rax + LIB_ELF_STRUCTURE_DYNAMIC_SYMBOL.address]
; 	add	rsi,	KERNEL_EXEC_BASE_address

; 	; update executable local function address
; 	mov	qword [r9 + rax + LIB_ELF_STRUCTURE_DYNAMIC_SYMBOL.address],	rsi

; 	; insert function address to GOT at RCX offset
; 	mov	qword [r11 + r12 * 0x08],	rsi

; 	; next relocation
; 	jmp	.function_next

; .function_global:
	; set pointer to function name
	mov	esi,	dword [r9 + rax]
	add	rsi,	r10

	; calculate function name length
	call	lib_string_length

	; retrieve function address
	call	kernel_library_function

	; insert function address to GOT at RCX offset
	mov	qword [r11 + r12 * 0x08],	rax

.function_next:
	; move pointer to next entry
	add	r8,	LIB_ELF_STRUCTURE_DYNAMIC_RELOCATION.SIZE

	; next function index
	inc	r12

	; no more entries?
	sub	rbx,	LIB_ELF_STRUCTURE_DYNAMIC_RELOCATION.SIZE
	jnz	.function	; no

.end:
	; restore original registers
	pop	r13
	pop	r12
	pop	r11
	pop	r10
	pop	r9
	pop	r8
	pop	rsi
	pop	rdx
	pop	rcx
	pop	rbx
	pop	rax

	; return from routine
	ret

;-------------------------------------------------------------------------------
; in:
;	rcx - length of path
;	rsi - pointer to path
;	rbp - pointer to file descriptor
; out:
;	CF - if file not exist
kernel_exec_load:
	; preserve original registers
	push	rax
	push	rcx
	push	rsi
	push	r8

	; kernel environment variables/rountines base address
	mov	r8,	qword [kernel_environment_base_address]

	; get file properties
	movzx	eax,	byte [r8 + KERNEL_STRUCTURE.storage_root_id]
	call	kernel_storage_file

	; file exist?
	cmp	qword [rbp + KERNEL_STORAGE_STRUCTURE_FILE.id],	EMPTY
	je	.end	; no

	; prepare space for file content
	mov	rcx,	qword [rbp + KERNEL_STORAGE_STRUCTURE_FILE.size_byte]
	add	rcx,	~STATIC_PAGE_mask
	shr	rcx,	STATIC_PAGE_SIZE_shift
	call	kernel_memory_alloc

	; load file content into prepared space
	mov	rsi,	qword [rbp + KERNEL_STORAGE_STRUCTURE_FILE.id]
	call	kernel_storage_read

	; return file content address
	mov	qword [rbp + KERNEL_STORAGE_STRUCTURE_FILE.address],	rdi

.end:
	; restore original registers
	pop	r8
	pop	rsi
	pop	rcx
	pop	rax

	; return from routine
	ret

;-------------------------------------------------------------------------------
; in:
;	r13 - pointer to file content
; out:
;	rcx - farthest segment limit in Bytes
kernel_exec_size:
	; preserve original registers
	push	rbx
	push	rdx

	; number of header entries
	movzx	ebx,	word [r13 + LIB_ELF_STRUCTURE.header_entry_count]

	; length of memory space in Bytes
	xor	ecx,	ecx

	; beginning of header table
	mov	rdx,	qword [r13 + LIB_ELF_STRUCTURE.header_table_position]
	add	rdx,	r13

.calculate:
	; ignore empty entries
	cmp	dword [rdx + LIB_ELF_STRUCTURE_HEADER.type],	EMPTY
	je	.leave	; empty one
	cmp	qword [rdx + LIB_ELF_STRUCTURE_HEADER.memory_size],	EMPTY
	je	.leave	; this too

	; segment required in memory?
	cmp	dword [rdx + LIB_ELF_STRUCTURE_HEADER.type],	LIB_ELF_HEADER_TYPE_load
	jne	.leave	; no

	; this segment is after previous one?
	cmp	rcx,	qword [rdx + LIB_ELF_STRUCTURE_HEADER.virtual_address]
	ja	.leave	; no

	; remember end of segment address
	mov	rcx,	qword [rdx + LIB_ELF_STRUCTURE_HEADER.virtual_address]
	add	rcx,	qword [rdx + LIB_ELF_STRUCTURE_HEADER.segment_size]

.leave:
	; move pointer to next entry
	add	rdx,	LIB_ELF_STRUCTURE_HEADER.SIZE

	; end of table?
	dec	ebx
	jnz	.calculate	; no

	; restore original registers
	pop	rdx
	pop	rbx

	; return from routine
	ret