# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::BaseService do
  describe ".apply" do
    let(:aggregation_result) { BillableMetrics::Aggregations::BaseService::Result.new }

    context "when chargeable is not chargeable data" do
      it "raises an error" do
        expect do
          described_class.apply(chargeable: build(:fee), aggregation_result:)
        end.to raise_error(NotImplementedError, "Chargeable: Fee is not implemented")
      end
    end
  end
end
