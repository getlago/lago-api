# frozen_string_literal: true

# Per-company concurrency rule of the QuickBooks integration jobs. sidekiq-throttled calls it with the
# serialized ActiveJob arguments on every fetch and finalize of every provider's job, so it never
# raises and never loads a record: anything it cannot resolve gets no limit.
# It has no organization context: it reads ids by primary key from the job's own global id and
# returns only a number and a digest.
module IntegrationThrottleKey
  QUICKBOOKS_TYPE = "Integrations::QuickbooksIntegration"
  LIMIT = 3
  NO_CONNECTION_SUFFIX = "none"
  CACHE_TTL = 1.hour
  THREAD_KEY = :integration_throttle_key
  RECORD_KEYS = %w[invoice credit_note payment].freeze
  RECORD_CLASSES = %w[Invoice CreditNote Payment].freeze

  # The gem asks for the limit, then for the key suffix, on the thread that later finalizes the job.
  # The suffix reuses the resolution of the limit for the same arguments: a second resolution that
  # fails or changes would count the job under "none", or free a slot in another set than the one it took.
  def self.limit(*args)
    key = company_key(args)
    Thread.current[THREAD_KEY] = [args, key]
    key ? LIMIT : nil
  end

  def self.key_suffix(*args)
    resolved_args, resolved_key = Thread.current[THREAD_KEY]
    key = (resolved_args == args) ? resolved_key : company_key(args)
    key ? Digest::SHA256.hexdigest(key) : NO_CONNECTION_SUFFIX
  end

  # A payload of any other shape (no argument, not a hash, no global id) is expected and resolves to
  # nil in silence. A database or cache error resolves to nil too, with one warning without ids:
  # the gem only logs when this rule raises, so a permanent failure would turn the cap off unseen.
  def self.company_key(args)
    payload = args.first
    return unless payload.is_a?(Hash)

    payload = payload.with_indifferent_access
    from_integration = payload.key?(:integration)
    entry = from_integration ? payload[:integration] : payload.values_at(*RECORD_KEYS).compact.first
    return unless entry.is_a?(Hash) && entry[:_aj_globalid].is_a?(String)

    gid = GlobalID.parse(entry[:_aj_globalid])
    return unless gid

    if from_integration
      cached(gid) { company_key_for(gid.model_id) } if gid.model_name == QUICKBOOKS_TYPE
    elsif RECORD_CLASSES.include?(gid.model_name)
      cached(gid) do
        integration_id = lookup(gid.model_name.constantize, gid.model_id)
        company_key_for(integration_id) if integration_id
      end
    end
  rescue => e
    warn_fail_open(e)
    nil
  end

  # The logger cannot break the never-raise contract.
  def self.warn_fail_open(error)
    Rails.logger.warn("IntegrationThrottleKey fail open: #{error.class}")
  rescue
    nil
  end

  # A nil result is stored too, so a customer without QuickBooks costs one lookup per hour.
  def self.cached(gid, &)
    Rails.cache.fetch("integration_throttle_key/#{gid.model_name}/#{gid.model_id}", expires_in: CACHE_TTL, &)
  end

  # The value Integrations::Aggregator::BaseService#throttle_key counts the QuickBooks rate limit on,
  # so both limits apply to the same company, sandbox and production apart. Without a company id,
  # the integration id stands in, as the connection id does for the rate limit.
  def self.company_key_for(integration_id)
    realm_id, sandbox = Integrations::QuickbooksIntegration.where(id: integration_id)
      .pick(Arel.sql("settings->>'realm_id'"), Arel.sql("settings->>'sandbox'"))
    return integration_id if realm_id.blank?

    "#{(sandbox == "true") ? "quickbooks-sandbox" : "quickbooks"}:#{realm_id}"
  end

  def self.lookup(klass, id)
    customer_id = klass.unscoped.where(id:).pick(:customer_id)
    return unless customer_id

    # The record jobs sync to the customer's first accounting link, read as customer.integration_customers
    # .accounting_kind.first: when that link is NetSuite or Xero, QuickBooks is not called.
    type, integration_id = IntegrationCustomers::BaseCustomer.where(customer_id:).accounting_kind
      .order(:id).pick(:type, :integration_id)
    integration_id if type == "IntegrationCustomers::QuickbooksCustomer"
  end

  private_class_method :company_key, :warn_fail_open, :cached, :company_key_for, :lookup
end
