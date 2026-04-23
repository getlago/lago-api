# frozen_string_literal: true

module PricingImports
  class ExecuteService < BaseService
    Result = BaseResult[:pricing_import]

    def initialize(pricing_import:)
      @pricing_import = pricing_import
      super
    end

    def call
      pricing_import.processing!
      pricing_import.update!(execution_report: [], progress_current: 0)

      plan = pricing_import.edited_plan || {}
      bm_code_to_id = create_billable_metrics!(plan["billable_metrics"] || [])
      create_plans!(plan["plans"] || [], bm_code_to_id)

      pricing_import.complete!
      result.pricing_import = pricing_import
      result
    rescue => e
      pricing_import.fail!(e.message)
      raise
    end

    private

    attr_reader :pricing_import

    def organization
      pricing_import.organization
    end

    def create_billable_metrics!(items)
      code_to_id = {}

      items.each do |bm_input|
        input = bm_input.deep_symbolize_keys
        res = BillableMetrics::CreateService.call(input.merge(organization_id: organization.id))

        record_result!(kind: "billable_metric", input: bm_input, result: res) do |r|
          r.try(:billable_metric)&.id
        end

        code_to_id[bm_input["code"]] = res.billable_metric.id if res.success? && res.billable_metric
      end

      code_to_id
    end

    def create_plans!(items, bm_code_to_id)
      items.each do |plan_input|
        charges = (plan_input["charges"] || []).map do |c|
          c = c.dup
          if c["billable_metric_code"] && bm_code_to_id[c["billable_metric_code"]]
            c["billable_metric_id"] = bm_code_to_id[c["billable_metric_code"]]
          else
            existing = organization.billable_metrics.find_by(code: c["billable_metric_code"])
            c["billable_metric_id"] = existing.id if existing
          end
          c.delete("billable_metric_code")
          c["pay_in_advance"] = false unless c.key?("pay_in_advance")
          c["invoiceable"] = true unless c.key?("invoiceable")
          c.deep_symbolize_keys
        end

        params = plan_input.deep_symbolize_keys.merge(
          organization_id: organization.id,
          charges: charges,
          pay_in_advance: plan_input.fetch("pay_in_advance", false),
          amount_currency: plan_input["amount_currency"] || "USD"
        )

        res = Plans::CreateService.call(params)

        record_result!(kind: "plan", input: plan_input, result: res) do |r|
          r.try(:plan)&.id
        end
      end
    end

    def record_result!(kind:, input:, result:)
      created_id = result.success? ? yield(result) : nil
      error = result.success? ? nil : extract_error(result)

      report = pricing_import.execution_report.dup
      report << {
        kind: kind,
        code: input["code"],
        name: input["name"],
        success: result.success?,
        created_id: created_id,
        error: error
      }

      pricing_import.update!(
        execution_report: report,
        progress_current: pricing_import.progress_current + 1
      )
    end

    def extract_error(result)
      return result.error.message if result.error.respond_to?(:message)

      result.error.to_s
    end
  end
end
