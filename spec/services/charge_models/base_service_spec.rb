# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::BaseService do
  describe ".apply" do
    let(:aggregation_result) { BillableMetrics::Aggregations::BaseService::Result.new }

    context "when structure is not pricing structure" do
      it "raises an error" do
        expect do
          described_class.apply(pricing_structure: build(:fee), aggregation_result:)
        end.to raise_error(NotImplementedError, "Pricing structure: Fee is not implemented")
      end
    end
  end
end
