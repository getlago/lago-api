# frozen_string_literal: true

require "rails_helper"

RSpec.describe PricingUnits::CreateService do
  describe "#call" do
    subject(:result) { described_class.call(params) }

    let_it_be(:organization) { create(:organization) }
    let(:name) { "Cloud tokens" }
    let(:short_name) { "CT" }
    let(:description) { "description" }
    let(:already_used_code) { "credits" }

    let(:params) do
      {
        organization:,
        name:,
        code:,
        short_name:,
        description:
      }
    end

    before { create(:pricing_unit, code: already_used_code, organization:) }

    context "with premium organization", :premium do
      context "when params are valid" do
        let(:code) { "tokens" }

        it "returns a successful result with the pricing unit" do
          expect(result).to be_success

          expect(result.pricing_unit)
            .to be_a(PricingUnit)
            .and have_attributes(params)
        end

        it "creates pricing unit" do
          expect { result }.to change(PricingUnit, :count).by(1)
        end
      end

      context "when params are invalid" do
        let(:code) { already_used_code }

        it "fails with validation error" do
          expect(result).to be_failure
          expect(result.error.messages).to match(code: ["value_already_exist"])
        end

        it "does not create pricing unit" do
          expect { result }.not_to change(PricingUnit, :count)
        end
      end

      context "when a concurrent create took the code" do
        let(:code) { "tokens" }
        let(:constraint) { "index_pricing_units_on_code_and_organization_id" }
        let(:database_result) { instance_double(PG::Result, error_field: constraint) }
        let(:database_error) { PG::UniqueViolation.new("duplicate value") }
        let(:write_error) { ActiveRecord::RecordNotUnique.new("duplicate value") }

        before do
          allow(database_error).to receive(:result).and_return(database_result)
          allow(PricingUnit).to receive(:create!) { raise write_error, cause: database_error }
        end

        it "fails with value_already_exist on code" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq(code: ["value_already_exist"])
        end

        context "with another constraint" do
          let(:constraint) { "pricing_units_pkey" }

          it "raises the database error" do
            expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
          end
        end
      end
    end

    context "with freemium organization" do
      context "when params are valid" do
        let(:code) { "tokens" }

        it "fails with a forbidden error" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("feature_unavailable")
        end

        it "does not create pricing unit" do
          expect { result }.not_to change(PricingUnit, :count)
        end
      end

      context "when params are invalid" do
        let(:code) { already_used_code }

        it "fails with a forbidden error" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("feature_unavailable")
        end

        it "does not create pricing unit" do
          expect { result }.not_to change(PricingUnit, :count)
        end
      end
    end
  end
end
