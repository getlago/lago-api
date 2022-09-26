# frozen_string_literal: true

class TaskNotFoundError < StandardError
end

class MigrationTaskJob < ApplicationJob
  queue_as 'default'

  retry_on TaskNotFoundError, attempts: 5

  def perform(task_name)
    LagoApi::Application.load_tasks
    raise(TaskNotFoundError) unless Rake::Task.task_defined?(task_name)

    Rake::Task[task_name].invoke
  end
end
