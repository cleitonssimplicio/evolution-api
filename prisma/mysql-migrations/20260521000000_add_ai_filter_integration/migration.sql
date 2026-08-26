-- CreateTable
CREATE TABLE `AiFilterBot` (
    `id` VARCHAR(191) NOT NULL,
    `enabled` BOOLEAN NOT NULL DEFAULT true,
    `description` VARCHAR(255) NULL,
    `openaiCredsId` VARCHAR(191) NOT NULL,
    `model` VARCHAR(100) NOT NULL DEFAULT 'gpt-4o-mini',
    `apiBaseUrl` VARCHAR(255) NULL,
    `systemPrompt` TEXT NULL,
    `filterCategories` JSON NULL,
    `autoRespondPrompt` TEXT NULL,
    `expire` INT NULL DEFAULT 0,
    `keywordFinish` VARCHAR(100) NULL,
    `delayMessage` INT NULL,
    `unknownMessage` VARCHAR(100) NULL,
    `listeningFromMe` BOOLEAN NULL DEFAULT false,
    `stopBotFromMe` BOOLEAN NULL DEFAULT false,
    `keepOpen` BOOLEAN NULL DEFAULT false,
    `debounceTime` INT NULL,
    `ignoreJids` JSON NULL,
    `splitMessages` BOOLEAN NULL DEFAULT false,
    `timePerChar` INT NULL DEFAULT 0,
    `triggerType` ENUM('all', 'keyword', 'none', 'advanced') NULL,
    `triggerOperator` ENUM('contains', 'equals', 'startsWith', 'endsWith', 'regex') NULL,
    `triggerValue` VARCHAR(191) NULL,
    `createdAt` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    `updatedAt` TIMESTAMP NOT NULL,
    `instanceId` VARCHAR(191) NOT NULL,

    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `AiFilterSetting` (
    `id` VARCHAR(191) NOT NULL,
    `expire` INT NULL DEFAULT 0,
    `keywordFinish` VARCHAR(100) NULL,
    `delayMessage` INT NULL,
    `unknownMessage` VARCHAR(100) NULL,
    `listeningFromMe` BOOLEAN NULL DEFAULT false,
    `stopBotFromMe` BOOLEAN NULL DEFAULT false,
    `keepOpen` BOOLEAN NULL DEFAULT false,
    `debounceTime` INT NULL,
    `ignoreJids` JSON NULL,
    `splitMessages` BOOLEAN NULL DEFAULT false,
    `timePerChar` INT NULL DEFAULT 0,
    `createdAt` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    `updatedAt` TIMESTAMP NOT NULL,
    `botIdFallback` VARCHAR(100) NULL,
    `instanceId` VARCHAR(191) NOT NULL,

    UNIQUE INDEX `AiFilterSetting_instanceId_key`(`instanceId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `AiFilterBot` ADD CONSTRAINT `AiFilterBot_instanceId_fkey` FOREIGN KEY (`instanceId`) REFERENCES `Instance`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `AiFilterBot` ADD CONSTRAINT `AiFilterBot_openaiCredsId_fkey` FOREIGN KEY (`openaiCredsId`) REFERENCES `OpenaiCreds`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `AiFilterSetting` ADD CONSTRAINT `AiFilterSetting_instanceId_fkey` FOREIGN KEY (`instanceId`) REFERENCES `Instance`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `AiFilterSetting` ADD CONSTRAINT `AiFilterSetting_botIdFallback_fkey` FOREIGN KEY (`botIdFallback`) REFERENCES `AiFilterBot`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
