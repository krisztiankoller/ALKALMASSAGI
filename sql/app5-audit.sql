USE [app5_audit];

IF SCHEMA_ID(N'dbo') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA [dbo]');
END;

IF OBJECT_ID(N'dbo.audit_events', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[audit_events] (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        event_time DATETIME2 NOT NULL
            CONSTRAINT [DF_app5_audit_audit_events_event_time]
            DEFAULT SYSUTCDATETIME(),
        service_name NVARCHAR(128) NOT NULL,
        direction NVARCHAR(32) NOT NULL,
        source_topic NVARCHAR(255) NULL,
        destination_topic NVARCHAR(255) NULL,
        message_key NVARCHAR(512) NULL,
        payload NVARCHAR(MAX) NULL,
        status NVARCHAR(64) NOT NULL,
        error_message NVARCHAR(MAX) NULL
    );
END;

IF COL_LENGTH(N'dbo.audit_events', N'event_time') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events]
        ADD event_time DATETIME2 NOT NULL
            CONSTRAINT [DF_app5_audit_audit_events_event_time]
            DEFAULT SYSUTCDATETIME();
END;

IF COL_LENGTH(N'dbo.audit_events', N'service_name') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD service_name NVARCHAR(128) NULL;
END;

IF COL_LENGTH(N'dbo.audit_events', N'direction') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD direction NVARCHAR(32) NULL;
END;

IF COL_LENGTH(N'dbo.audit_events', N'source_topic') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD source_topic NVARCHAR(255) NULL;
END;

IF COL_LENGTH(N'dbo.audit_events', N'destination_topic') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD destination_topic NVARCHAR(255) NULL;
END;

IF COL_LENGTH(N'dbo.audit_events', N'message_key') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD message_key NVARCHAR(512) NULL;
END;

IF COL_LENGTH(N'dbo.audit_events', N'payload') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD payload NVARCHAR(MAX) NULL;
END;

IF COL_LENGTH(N'dbo.audit_events', N'status') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD status NVARCHAR(64) NULL;
END;

IF COL_LENGTH(N'dbo.audit_events', N'error_message') IS NULL
BEGIN
    ALTER TABLE [dbo].[audit_events] ADD error_message NVARCHAR(MAX) NULL;
END;
