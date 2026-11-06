# frozen_string_literal: true

module Organizations
  # Creates a self-serve production organization and its sandbox, each with its own API key and billing entity, all
  # or nothing. Callers gate on self-serve; this service does not.
  class CreateSelfServeService < BaseService
    Result = BaseResult[:organization, :sandbox_organization]

    SANDBOX_NAME_SUFFIX = " Sandbox"
    SANDBOX_SLUG_SUFFIX = "-sandbox"
    # 32 characters of the production slug plus the suffix fill the 40-character slug cap.
    SANDBOX_SLUG_BASE_LENGTH = 32

    def initialize(name:, document_numbering: "per_organization", timezone: nil, premium_integrations: [], feature_flags: [])
      @name = name
      @document_numbering = document_numbering
      @timezone = timezone
      @premium_integrations = premium_integrations
      @feature_flags = feature_flags
      super
    end

    def call
      name_result = ValidateNameService.call(name:)
      return result.fail_with_error!(name_result.error) unless name_result.success?

      unless Array(feature_flags).all? { FeatureFlag.valid?(it) }
        return result.validation_failure!(errors: {feature_flags: ["value_is_invalid"]})
      end

      ActiveRecord::Base.transaction do
        production = CreateService.call!(**shared_attributes, name: name_result.name, environment: "production")
          .organization
        sandbox = CreateService.call!(
          **shared_attributes,
          name: "#{name_result.name}#{SANDBOX_NAME_SUFFIX}",
          slug: sandbox_slug(production),
          environment: "sandbox",
          production_organization_id: production.id
        ).organization

        result.organization = production
        result.sandbox_organization = sandbox
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :name, :document_numbering, :timezone, :premium_integrations, :feature_flags

    def shared_attributes
      {document_numbering:, timezone:, premium_integrations: Array(premium_integrations),
       feature_flags: Array(feature_flags), self_serve: true}
    end

    # A taken slug gets a short random suffix. A concurrent writer of the same slug hits the unique index, which
    # CreateService answers as value_already_exist on slug.
    def sandbox_slug(production)
      base = production.slug.first(SANDBOX_SLUG_BASE_LENGTH).sub(/-+\z/, "")
      candidate = "#{base}#{SANDBOX_SLUG_SUFFIX}"
      while Organization.exists?(slug: candidate)
        candidate = "#{base.first(28).sub(/-+\z/, "")}#{SANDBOX_SLUG_SUFFIX}-#{SecureRandom.alphanumeric(3).downcase}"
      end
      candidate
    end
  end
end
