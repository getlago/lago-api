# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  LIMIT = 10

  SIGNATURE_ALGOS = [
    :jwt,
    :hmac,
    :standard_webhooks
  ].freeze

  WEBHOOK_EVENT_TYPE_CONFIG = YAML.safe_load_file(
    Rails.root.join("config/webhook_event_types.yml"),
    symbolize_names: true
  ).freeze

  WEBHOOK_EVENT_TYPES = WEBHOOK_EVENT_TYPE_CONFIG.map do |_, config|
    config[:name].to_s
  end.freeze

  PRODUCT_CATALOG_ONLY_EVENT_TYPES = WEBHOOK_EVENT_TYPE_CONFIG.values
    .select { |config| config[:product_catalog_only] }
    .map { |config| config[:name] }
    .to_set
    .freeze

  # Former names, still accepted from API clients and mapped to the current one.
  RENAMED_EVENT_TYPES = {"credit_note.provider_refund_failure" => "credit_note.refund_failure"}.freeze

  V2_ERROR_CODES = {invalid_types: "value_is_invalid", exceeded_limit: "exceeded_limit"}.freeze

  belongs_to :organization
  has_many :webhooks, dependent: :delete_all
  has_many :signing_keys, class_name: "WebhookEndpointSigningKey", dependent: :delete_all
  has_many :usable_signing_keys, -> { usable.order(:created_at, :id) }, class_name: "WebhookEndpointSigningKey"

  validates :webhook_url, presence: true, url: {block_private_addresses: true}
  validates :webhook_url, uniqueness: {scope: :organization_id}
  validate :max_webhook_endpoints, on: :create
  validate :validate_event_types, if: :event_types_changed?
  # Existing endpoints keep their algorithm when the organization no longer allows it.
  validate :validate_signature_algo_allowed, if: -> { new_record? || signature_algo_changed? }

  before_validation :normalize_event_types, if: :event_types_changed?

  enum :signature_algo, SIGNATURE_ALGOS, validate: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[webhook_url]
  end

  # v1 and GraphQL clients read the sentences of these errors; native v2 renders a token in their place.
  def self.validation_codes(errors)
    errors.group_by_attribute.transform_values do |attribute_errors|
      attribute_errors.map { V2_ERROR_CODES.fetch(it.type, it.message) }
    end
  end

  # The algorithms the organization accepts are returned with the error, so a client can fix its request.
  def self.validation_meta(record, meta)
    return meta unless record.errors.include?(:signature_algo)

    meta.merge(signature_algo: {allowed_values: record.allowed_signature_algos})
  end

  def self.default_signature_algo(organization)
    organization.product_catalog_enabled? ? "standard_webhooks" : "jwt"
  end

  # Product catalog organizations sign with Standard Webhooks only. Other organizations get it with the rollout flag.
  def allowed_signature_algos
    return %w[standard_webhooks] if organization&.product_catalog_enabled?

    algos = %w[jwt hmac]
    algos << "standard_webhooks" if organization&.feature_flag_enabled?(:standard_webhooks_signature)
    algos
  end

  # The keys an endpoint shows in every API. A jwt or hmac endpoint that kept the key of a former switch does not sign with it.
  def active_signing_keys
    standard_webhooks? ? usable_signing_keys : WebhookEndpointSigningKey.none
  end

  private

  def validate_signature_algo_allowed
    # An unknown value already fails the enum validation.
    return unless self.class.signature_algos.key?(signature_algo.to_s)
    return if allowed_signature_algos.include?(signature_algo.to_s)

    errors.add(:signature_algo, :inclusion)
  end

  def max_webhook_endpoints
    errors.add(:base, :exceeded_limit) if organization &&
      organization.webhook_endpoints.reload.count >= LIMIT
  end

  def validate_event_types
    return if event_types.nil?

    # since AR casts non-array values to [] we need to check the raw value
    if event_types.is_a?(Array) && event_types.blank? && !event_types_before_type_cast.is_a?(Array)
      errors.add(:event_types, :must_be_array)
    end

    invalid_types = event_types - WEBHOOK_EVENT_TYPES
    if invalid_types.present?
      errors.add(:event_types, :invalid_types, invalid_types:)
    end
  end

  def normalize_event_types
    return if event_types.blank?

    normalized = event_types
      .map { |event_type| event_type&.to_s&.strip&.downcase }
      .reject(&:blank?)
      .map { |event_type| RENAMED_EVENT_TYPES.fetch(event_type, event_type) }
      .uniq

    # special case: convert ["*"] to nil to disable filtering
    if normalized.length == 1 && normalized.first == "*"
      normalized = nil
    end

    self.event_types = normalized
  end
end

# == Schema Information
#
# Table name: webhook_endpoints
# Database name: primary
#
#  id              :uuid             not null, primary key
#  event_types     :string           is an Array
#  name            :string
#  signature_algo  :integer          default("jwt"), not null
#  webhook_url     :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_webhook_endpoints_on_organization_id                  (organization_id)
#  index_webhook_endpoints_on_webhook_url_and_organization_id  (webhook_url,organization_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
