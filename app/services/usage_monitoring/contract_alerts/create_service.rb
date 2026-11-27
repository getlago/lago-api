# frozen_string_literal: true

module UsageMonitoring
  module ContractAlerts
    class CreateService < BaseService
      include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

      Result = BaseResult[:alert]

      SCOPE_FIELDS = %w[type product_code product_filter_codes with_product_filters].freeze

      def initialize(organization:, contract:, params:)
        @organization = organization
        @contract = contract
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        return result.not_found_failure!(resource: "contract") unless contract
        return result.forbidden_failure! unless License.premium? && organization.feature_flag_enabled?(:contract_alerts)
        return result.forbidden_failure!(code: "contract_not_live") unless Contract::LIVE_STATUSES.include?(contract.status)

        if params[:alert_type].blank?
          return result.single_validation_failure!(field: :alert_type, error_code: "value_is_mandatory")
        end

        unless ContractAlert::STI_MAPPING.key?(params[:alert_type].to_s)
          return result.single_validation_failure!(field: :alert_type, error_code: "invalid_type")
        end

        entry = read_scope
        return result unless result.success?

        thresholds_result = UsageMonitoring::Thresholds::ValidateService.call(thresholds: params[:thresholds])
        return result.fail_with_error!(thresholds_result.error) unless thresholds_result.success?

        product = find_product(entry)
        return result unless result.success?

        product_filter = find_product_filter(product, entry&.dig(:product_filter_codes)&.first)
        return result unless result.success?

        ActiveRecord::Base.transaction do
          alert = ContractAlert.create!(
            organization:,
            contract_external_id: contract.external_id,
            alert_type: params[:alert_type].to_s,
            code: params[:code],
            name: params[:name],
            product:,
            product_filter:,
            with_product_filters: entry&.dig(:with_product_filters) == true
          )
          alert.thresholds.create!(prepare_thresholds(params[:thresholds], organization.id))
          seed_alarms_already_past(alert, contract)

          # An alert created above its thresholds fires at the next evaluation, without waiting for an event
          after_commit { UsageMonitoring::TrackContractActivityService.call!(contract:) }

          result.alert = alert
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        if violated_unique_index(e) == "idx_contract_alerts_scope_with_filters_unique"
          result.single_validation_failure!(field: :base, error_code: "alert_already_exists")
        else
          unique_index_failure!(e, "idx_contract_alerts_code_unique" => :code)
        end
      end

      private

      attr_reader :organization, :contract, :params

      def read_scope
        scope = params[:scope]
        return validation_error(:scope, "value_is_mandatory") if scope.nil?
        return validation_error(:scope, "value_is_invalid") unless scope.is_a?(Array)
        return validation_error(:scope, "value_is_invalid", max_items: 1) if scope.many?
        return if scope.empty?

        entry = scope.first
        return validation_error(scope_field(:base), "value_is_invalid") unless entry.is_a?(Hash)

        unknown = entry.keys - SCOPE_FIELDS
        return validation_error(scope_field(unknown.first), "value_is_invalid") if unknown.any?
        return validation_error(scope_field(:type), "value_is_invalid", allowed_values: ["contract"]) unless entry[:type] == "contract"
        return validation_error(scope_field(:product_code), "value_is_mandatory") if entry[:product_code].blank?
        return validation_error(scope_field(:product_code), "value_is_invalid") unless entry[:product_code].is_a?(String)

        codes = entry[:product_filter_codes]
        if (codes && entry.key?(:with_product_filters)) || [nil, true, false].exclude?(entry[:with_product_filters])
          return validation_error(scope_field(:with_product_filters), "value_is_invalid")
        end

        if codes
          return validation_error(scope_field(:product_filter_codes), "value_is_invalid", max_items: 1) if codes.is_a?(Array) && codes.many?
          return validation_error(scope_field(:product_filter_codes), "value_is_invalid") unless codes.is_a?(Array) && codes.first.is_a?(String) && codes.first.present?
        end

        entry
      end

      def scope_field(name)
        ValidationFailure.item_field(:scope, 0, name)
      end

      def validation_error(field, error_code, **meta)
        result.single_validation_failure!(field:, error_code:, meta:)
      end

      def find_product(entry)
        if entry.nil?
          validation_error(:scope, "product_required_for_units") if params[:alert_type].to_s == "usage_units"
          return
        end

        product = organization.products.where(id: priced_rate_cards.select(:product_id)).find_by(code: entry[:product_code])

        if product.nil?
          result.not_found_failure!(resource: "product")
          nil
        elsif product.fixed?
          validation_error(scope_field(:product_code), "value_is_invalid")
          nil
        else
          product
        end
      end

      def find_product_filter(product, code)
        return if code.nil?

        product_filter = product.filters
          .where(id: priced_rate_cards.where(product_id: product.id).select(:product_filter_id))
          .find_by(code:)

        result.not_found_failure!(resource: "product_filter") unless product_filter
        product_filter
      end

      def priced_rate_cards
        live_contracts = organization.contracts.live.where(external_id: contract.external_id)

        RateCard.where(
          organization_id: organization.id,
          id: ContractRateCard.where(contract_id: live_contracts.select(:id)).select(:rate_card_id)
        )
      end
    end
  end
end
