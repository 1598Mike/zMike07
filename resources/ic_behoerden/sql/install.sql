-- ic_behoerden · Datenbankschema
-- Die Ressource führt diese Datei beim Start selbst aus (Config.AutoInstallSql = false schaltet das ab).
-- Alle Anweisungen sind wiederholbar (IF NOT EXISTS). Jede Tabelle hat Index-Spalten und die vollständige Zeile als JSON in "data".

CREATE TABLE IF NOT EXISTS `ic_applications` (
  `id` VARCHAR(20) NOT NULL,
  `case_no` VARCHAR(24) NULL,
  `kind` VARCHAR(12) NULL,
  `status` VARCHAR(20) NULL,
  `applicant_char` VARCHAR(64) NULL,
  `name` VARCHAR(120) NULL,
  `data` LONGTEXT NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ic_applications_case_no` (`case_no`),
  KEY `ix_ic_applications_status` (`status`),
  KEY `ix_ic_applications_applicant` (`applicant_char`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_entities` (
  `id` VARCHAR(20) NOT NULL,
  `reg_no` VARCHAR(24) NULL,
  `kind` VARCHAR(12) NULL,
  `status` VARCHAR(20) NULL,
  `name` VARCHAR(120) NULL,
  `data` LONGTEXT NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ic_entities_reg_no` (`reg_no`),
  KEY `ix_ic_entities_status` (`status`),
  KEY `ix_ic_entities_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_appointments` (
  `id` VARCHAR(20) NOT NULL,
  `status` VARCHAR(20) NULL,
  `booker_char` VARCHAR(64) NULL,
  `starts_at` BIGINT NULL,
  `data` LONGTEXT NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_ic_appointments_status` (`status`),
  KEY `ix_ic_appointments_booker` (`booker_char`),
  KEY `ix_ic_appointments_starts` (`starts_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_office_hours` (
  `id` VARCHAR(20) NOT NULL,
  `official_char` VARCHAR(64) NULL,
  `starts_at` BIGINT NULL,
  `ends_at` BIGINT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_ic_office_hours_official` (`official_char`),
  KEY `ix_ic_office_hours_starts` (`starts_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_blacklist` (
  `id` VARCHAR(20) NOT NULL,
  `term` VARCHAR(80) NULL,
  `reason` VARCHAR(120) NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_settings` (
  `id` VARCHAR(40) NOT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_strikes` (
  `id` VARCHAR(20) NOT NULL,
  `char_id` VARCHAR(64) NULL,
  `ts` BIGINT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_ic_strikes_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_chars` (
  `id` VARCHAR(64) NOT NULL,
  `notify_on_duty` TINYINT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_notices` (
  `id` VARCHAR(20) NOT NULL,
  `char_id` VARCHAR(64) NULL,
  `ts` BIGINT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_ic_notices_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ic_refunds` (
  `id` VARCHAR(20) NOT NULL,
  `char_id` VARCHAR(64) NULL,
  `ts` BIGINT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_ic_refunds_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Protokoll: nur anfügen, nie ändern
CREATE TABLE IF NOT EXISTS `ic_audit` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `ts` BIGINT NOT NULL,
  `actor` VARCHAR(120) NULL,
  `kind` VARCHAR(12) NULL,
  `action` VARCHAR(80) NULL,
  `target` VARCHAR(80) NULL,
  `detail` TEXT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_ic_audit_ts` (`ts`),
  KEY `ix_ic_audit_target` (`target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
