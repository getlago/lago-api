ALTER TABLE default.api_logs
    MODIFY COLUMN `http_method` Enum8('get' = 1, 'post' = 2, 'put' = 3, 'delete' = 4, 'patch' = 5);
