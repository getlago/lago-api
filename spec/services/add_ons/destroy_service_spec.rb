# frozen_string_literal: true

require "rails_helper"

RSpec.describe AddOns::DestroyService do
  subject(:destroy_service) { described_class.new(add_on:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:add_on) { create(:add_on, organization:) }

  describe "#call" do
    before { add_on }

    it "soft deletes the add-on" do
      aggregate_failures do
        expect { destroy_service.call }.to change(AddOn, :count).by(-1)
          .and change { add_on.reload.deleted_at }.from(nil)
      end
    end

    context "when add-on is not found" do
      let(:add_on) { nil }

      it "returns an error" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq("add_on_not_found")
        end
      end
    end
  end
end
