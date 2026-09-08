# frozen_string_literal: true

class QuoteVersion < ApplicationRecord
  include Currencies
  include Sequenced

  STATUSES = {
    draft: "draft",
    approved: "approved",
    voided: "voided"
  }.freeze

  VOID_REASONS = {
    manual: "manual",
    superseded: "superseded",
    cascade_of_expired: "cascade_of_expired",
    cascade_of_voided: "cascade_of_voided"
  }.freeze

  CASCADE_VOID_REASONS = VOID_REASONS.slice(:cascade_of_expired, :cascade_of_voided).freeze

  # The quote sharing feature (public share link via `share_token`) is not ready yet:
  # no share endpoint, no consumer of the token. Ignore the column so the app stops
  # reading/writing it; the column stays in the database for when the feature lands
  # (its now-unused unique index has been dropped).
  self.ignored_columns += %w[share_token]

  belongs_to :organization
  belongs_to :quote
  belongs_to :billing_entity, optional: true
  has_one :order_form

  enum :status, STATUSES,
    default: :draft,
    validate: true
  enum :void_reason, VOID_REASONS,
    instance_methods: false,
    validate: {allow_nil: true}

  validates :currency, inclusion: {in: currency_list}, allow_nil: true

  validates :void_reason, :voided_at,
    presence: true,
    if: -> { voided? }

  validates :approved_at,
    presence: true,
    if: -> { approved? }

  sequenced(
    scope: ->(quote_version) { quote_version.quote.versions },
    lock_key: ->(quote_version) { quote_version.quote_id }
  )

  delegate :customer, to: :quote

  def version = sequential_id

  # A blank billing entity means the deal follows whichever entity will bill it, resolved at billing
  # time rather than frozen here, the same semantic Subscription and Wallet carry.
  #
  # An amendment restates a subscription already bound to an entity, and the plan change carries that
  # binding over, so the deal follows the target rather than the customer's own default: otherwise the
  # signed document would name one issuer while the execution billed under another. Subscription
  # resolves its own fallback to the customer, so the last hop only serves a quote without a target.
  #
  # Every hop is guarded: a version with no quote yet reads as having no entity.
  def billing_entity
    super || amended_subscription&.billing_entity || quote&.customer&.billing_entity
  end

  def applicable_billing_entity_id
    billing_entity_id ||
      amended_subscription&.applicable_billing_entity_id ||
      quote&.customer&.billing_entity_id
  end

  private

  # Only an amendment restates a running subscription. Any other order type may still carry one,
  # since the column is optional and only amendments require it, and its execution ignores that
  # subscription entirely: the document has to ignore it too rather than name an issuer nothing bills
  # under.
  def amended_subscription
    return unless quote&.order_type == "subscription_amendment"

    quote.subscription
  end
end

# == Schema Information
#
# Table name: quote_versions
# Database name: primary
#
#  id                :uuid             not null, primary key
#  approved_at       :datetime
#  billing_items     :jsonb
#  content           :text
#  currency          :string
#  mention_variables :jsonb
#  status            :enum             default("draft"), not null
#  void_reason       :enum
#  voided_at         :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  billing_entity_id :uuid
#  organization_id   :uuid             not null
#  quote_id          :uuid             not null
#  sequential_id     :integer          not null
#
# Indexes
#
#  index_quote_versions_on_billing_entity_id           (billing_entity_id)
#  index_quote_versions_on_organization_id             (organization_id)
#  index_quote_versions_on_quote_id                    (quote_id)
#  index_unique_quote_versions_on_quote_active_status  (quote_id) UNIQUE WHERE (status = ANY (ARRAY['draft'::quote_status, 'approved'::quote_status]))
#  index_unique_quote_versions_on_quote_sequential_id  (quote_id,sequential_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (billing_entity_id => billing_entities.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (quote_id => quotes.id)
#
