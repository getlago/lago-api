# frozen_string_literal: true

Rake::Task['db:migrate'].enhance do
  Rake::Task['db:clickhouse:filter'].invoke
end

if Rake::Task.task_defined?('db:schema:dump:clickhouse')
  Rake::Task['db:schema:dump:clickhouse'].enhance do
    Rake::Task['db:clickhouse:filter'].invoke
  end
end

namespace :db do
  desc 'Filter secrets from clickhouse schema file'
  task 'clickhouse:filter' => :environment do
    next unless Rails.env.development?

    migration_file = 'db/clickhouse_schema.rb'
    text = File.read(migration_file)
    new_contents = text.gsub(ENV.fetch('LAGO_KAFKA_BOOTSTRAP_SERVERS', ''), '*****')
    File.open(migration_file, 'w') { |file| file.puts new_contents }
  end
end
