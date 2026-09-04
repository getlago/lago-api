SELECT
    rd.organization_id,
    rd.id AS lago_id,
    rd.record_table AS table_name,
    rd.record_id AS lago_record_id,
    rd.deleted_at,
    rd.created_at,
    rd.updated_at
FROM record_deletions AS rd;
