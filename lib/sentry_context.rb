# frozen_string_literal: true

# Business context for the Sentry events, so that an error can be tied to the organization and
# the records it was raised for. Tags are searchable and show how many organizations an issue
# spans; breadcrumbs record the decisions taken before the error (retries, fallbacks).
#
# Every call is a no-op when Sentry is not initialized.
module SentryContext
  module_function

  # The arguments are already deserialized when the perform callbacks run, so the records come
  # from the GlobalIDs without a query. The tags live in the scope sentry-sidekiq opens per job.
  def tag_job(job)
    tags = {job_executions: job.executions}

    job_records(job.arguments).each do |record|
      tags[:"#{record.model_name.param_key}_id"] ||= record.id
      tags[:organization_id] ||= organization_id_of(record)
    end

    Sentry.set_tags(tags.compact)
  end

  def tag_request(organization:, user: nil)
    Sentry.set_tags(organization_id: organization.id) if organization
    Sentry.set_user(id: user.id) if user
  end

  def breadcrumb(category, message = nil, level: "info", **data)
    Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category:, message:, level:, data:))
  end

  # The name is resolved only for the events actually sent, so tagging a job or a request costs
  # no query.
  def add_organization_context(event)
    organization_id = event.tags[:organization_id] || event.tags["organization_id"]
    return event if organization_id.blank?

    name = Organization.where(id: organization_id).pick(:name)
    event.contexts[:organization] = {id: organization_id, name:} if name
    event
  rescue => e
    Rails.logger.warn("Sentry organization context failed: #{e.message}")
    event
  end

  def job_records(arguments)
    values = arguments.flat_map { it.is_a?(Hash) ? it.values : [it] }
    values.grep(ActiveRecord::Base)
  end

  def organization_id_of(record)
    return record.id if record.is_a?(Organization)

    record.organization_id if record.respond_to?(:organization_id)
  end

  private_class_method :job_records, :organization_id_of
end
