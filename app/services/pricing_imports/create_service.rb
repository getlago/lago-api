# frozen_string_literal: true

module PricingImports
  class CreateService < BaseService
    Result = BaseResult[:pricing_import]

    def initialize(organization:, membership:, source_filename:, file_text:)
      @organization = organization
      @membership = membership
      @source_filename = source_filename
      @file_text = file_text
      super
    end

    def call
      analyze_result = PricingImports::AnalyzeService.call(
        file_text: file_text,
        source_filename: source_filename
      )
      return analyze_result if analyze_result.failure?

      proposed_plan = analyze_result.proposed_plan || {}

      pricing_import = PricingImport.create!(
        organization: organization,
        membership: membership,
        source_filename: source_filename,
        proposed_plan: proposed_plan,
        edited_plan: proposed_plan,
        progress_total: compute_total(proposed_plan),
        state: "draft"
      )

      result.pricing_import = pricing_import
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :membership, :source_filename, :file_text

    def compute_total(plan)
      bm = (plan["billable_metrics"] || []).size
      pl = (plan["plans"] || []).size
      bm + pl
    end
  end
end
