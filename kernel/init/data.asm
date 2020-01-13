;===============================================================================
; Copyright (C) by Blackend.dev
;===============================================================================

kernel_init_string_error_memory		db	"Init: Memory map, error."
kernel_init_string_error_memory_end:
kernel_init_string_error_memory_low	db	"Not enough memory."
kernel_init_string_error_memory_low_end:
kernel_init_string_acpi_search		db	"Looking for a RSDP/XSDP table, "
kernel_init_string_acpi_search_end:
kernel_init_string_acpi_search_found:	db	"found.", STATIC_ASCII_NEW_LINE
kernel_init_string_acpi_search_found_end:
kernel_init_string_error_acpi		db	"not found."
kernel_init_string_error_acpi_end:
kernel_init_string_error_acpi_corrupted	db	"ACPI table, corrupted."
kernel_init_string_error_acpi_corrupted_end:
kernel_init_string_error_apic		db	"APIC table not found."
kernel_init_string_error_apic_end:
kernel_init_string_error_ioapic		db	"I/O APIC table not found."
kernel_init_string_error_ioapic_end:

kernel_init_string_welcome		db	STATIC_COLOR_ASCII_GREEN_LIGHT, "Welcome to Cyjon OS!", STATIC_COLOR_ASCII_GRAY, " (v", KERNEL_version, ".", KERNEL_revision, " ", KERNEL_architecture, ")", STATIC_ASCII_NEW_LINE
kernel_init_string_welcome_end:
kernel_init_string_video		db	STATIC_COLOR_ASCII_GREEN_LIGHT, "::", STATIC_COLOR_ASCII_DEFAULT, " Video resolution at ", STATIC_COLOR_ASCII_WHITE
kernel_init_string_video_end:
kernel_init_string_video_separator	db	STATIC_COLOR_ASCII_DEFAULT, "x", STATIC_COLOR_ASCII_WHITE
kernel_init_string_video_separator_end:
kernel_init_string_video_font		db	STATIC_COLOR_ASCII_GREEN_LIGHT, "::", STATIC_COLOR_ASCII_DEFAULT, " Font: ", STATIC_COLOR_ASCII_DEFAULT
kernel_init_string_video_font_end:
kernel_init_string_memory_size		db	STATIC_COLOR_ASCII_GREEN_LIGHT, "::", STATIC_COLOR_ASCII_DEFAULT, " Available ", STATIC_COLOR_ASCII_WHITE
kernel_init_string_memory_size_end:
kernel_init_string_memory_format	db	STATIC_COLOR_ASCII_DEFAULT, " KiB of RAM memory.", STATIC_ASCII_NEW_LINE
kernel_init_string_memory_format_end:

kernel_init_string			db	STATIC_ASCII_NEW_LINE, STATIC_COLOR_ASCII_BLUE_LIGHT, "    B l a c k e n d . d e v", STATIC_ASCII_NEW_LINE
					db	STATIC_COLOR_ASCII_GRAY, "  ---------------------------", STATIC_ASCII_NEW_LINE, STATIC_ASCII_NEW_LINE
kernel_init_string_end:


kernel_init_apic_semaphore		db	STATIC_FALSE
kernel_init_ioapic_semaphore		db	STATIC_FALSE
kernel_init_smp_semaphore		db	STATIC_FALSE
kernel_init_ap_semaphore		db	STATIC_FALSE
kernel_init_ap_count			db	STATIC_EMPTY

kernel_init_apic_id_highest		db	STATIC_EMPTY

kernel_init_services_list:
	dq	service_tresher
	dq	service_tx
	dq	service_network
	dq	service_http
	dq	service_shell

	; koniec usług
	dq	STATIC_EMPTY

kernel_init_boot_file:
	incbin	"build/boot"
kernel_init_boot_file_end:
