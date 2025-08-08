# frozen_string_literal: true

module DataApi
  module V1
    class ChargesController < DataApi::BaseController
      include PremiumFeatureOnly

      def bulk_forecasted_usage_amount
        charges_data = params[:charges] || []

        if charges_data.empty?
          render json: { error: "No charges provided" }, status: :bad_request
          return
        end

        charge_ids = charges_data.map { |cd| cd[:charge_id] }.compact.uniq
        charge_filter_ids = charges_data.map { |cd| cd[:charge_filter_id] }.compact.uniq.reject(&:blank?)

        charges_lookup = Charge.where(id: charge_ids).index_by(&:id)
        charge_filters_lookup = charge_filter_ids.any? ? 
                               ChargeFilter.where(id: charge_filter_ids).index_by(&:id) : {}

        results = []
        failed_charges = []

        charges_data.each do |charge_data|
          begin
            charge = charges_lookup[charge_data[:charge_id]]
            charge_filter = charge_data[:charge_filter_id].present? ? 
                           charge_filters_lookup[charge_data[:charge_filter_id]] : nil

            unless charge
              raise ActiveRecord::RecordNotFound, "Charge not found: #{charge_data[:charge_id]}"
            end

            if charge_data[:charge_filter_id].present? && !charge_filter
              raise ActiveRecord::RecordNotFound, "ChargeFilter not found: #{charge_data[:charge_filter_id]}"
            end

            percentile_results = {}

            [:units_10th, :units_50th, :units_90th].each do |percentile_key|
              units = charge_data[percentile_key]
              next unless units

              result = Charges::CalculatePriceService.call(
                units: units,
                charge: charge,
                charge_filter: charge_filter
              )

              if result.success?
                suffix = percentile_key.to_s.gsub('units_', '').gsub('th', 'th_percentile')
                percentile_results["charge_amount_cents_#{suffix}"] = result.charge_amount_cents * 100
                percentile_results["subscription_amount_cents_#{suffix}"] = result.subscription_amount_cents * 100
                percentile_results["total_amount_cents_#{suffix}"] = result.total_amount_cents * 100
              end
            end

            results << {
              charge_id: charge_data[:charge_id],
              charge_filter_id: charge_data[:charge_filter_id],
              **percentile_results
            }

          rescue => e
            failed_charges << {
              charge_id: charge_data[:charge_id],
              error: e.message
            }
          end
        end

        response_data = {
          results: results,
          failed_charges: failed_charges,
          processed_count: results.length,
          failed_count: failed_charges.length,
        }

        Rails.logger.info "[ChargesController] Response summary: #{response_data}"

        render json: response_data
      end

      def resource_name
        "analytic"
      end
    end
  end
end