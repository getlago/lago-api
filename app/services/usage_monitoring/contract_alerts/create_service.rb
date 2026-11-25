# frozen_string_literal: true

module UsageMonitoring
  module ContractAlerts
    class CreateService < BaseService
      include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

      Result = BaseResult[:alert]

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

        unless [nil, true, false].include?(params[:with_product_filters])
          return result.single_validation_failure!(field: :with_product_filters, error_code: "value_is_invalid")
        end

        thresholds_result = UsageMonitoring::Thresholds::ValidateService.call(thresholds: params[:thresholds])
        return result.fail_with_error!(thresholds_result.error) unless thresholds_result.success?

        product = find_product
        return result unless result.success?

        product_filter = find_product_filter(product)
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
            with_product_filters: params[:with_product_filters] == true
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

      def find_product
        if product_param.blank?
          if params[:alert_type].to_s == "usage_units"
            result.single_validation_failure!(field: :product_code, error_code: "product_required_for_units")
          elsif product_filter_param.present?
            result.single_validation_failure!(field: :product_code, error_code: "value_is_mandatory")
          end

          return
        end

        products = organization.products.where(id: priced_rate_cards.select(:product_id))
        product = params[:product_id].present? ? products.find_by(id: product_param) : products.find_by(code: product_param)

        if product.nil?
          result.not_found_failure!(resource: "product")
          nil
        elsif product.fixed?
          result.single_validation_failure!(field: :product_code, error_code: "value_is_invalid")
          nil
        else
          product
        end
      end

      def find_product_filter(product)
        return if product_filter_param.blank?

        filters = product.filters.where(id: priced_rate_cards.where(product_id: product.id).select(:product_filter_id))
        product_filter = if params[:product_filter_id].present?
          filters.find_by(id: product_filter_param)
        else
          filters.find_by(code: product_filter_param)
        end

        result.not_found_failure!(resource: "product_filter") unless product_filter
        product_filter
      end

      def product_param
        params[:product_id].presence || params[:product_code].presence
      end

      def product_filter_param
        params[:product_filter_id].presence || params[:product_filter_code].presence
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
