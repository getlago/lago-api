# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Subscriptions::Charges::FiltersController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }
  let(:external_id) { "sub_123" }
  let(:external_id_query_param) { external_id }
  let(:subscription) { create(:subscription, customer:, plan:, external_id:) }
  let(:charge) { create(:standard_charge, plan:, organization:, billable_metric:) }

  before do
    subscription
    charge
    billable_metric_filter
  end

  describe "GET /api/v1/subscriptions/:external_id/charges/:code/filters" do
    subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters") }

    let(:charge_filter) { create(:charge_filter, charge:, organization:) }

    before do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["us"], organization:)
    end

    it_behaves_like "requires API permission", "subscription", "read"

    it "returns a list of charge filters" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:filters]).to be_present
      expect(json[:filters].length).to eq(1)
      expect(json[:filters].first[:lago_id]).to eq(charge_filter.id)
    end

    it "returns pagination metadata" do
      subject

      expect(json[:meta]).to include(
        current_page: 1,
        next_page: nil,
        prev_page: nil,
        total_pages: 1,
        total_count: 1
      )
    end

    context "when subscription does not exist" do
      let(:external_id_query_param) { "invalid_external_id" }

      it "returns not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
      end
    end

    context "when charge does not exist" do
      subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/invalid_code/filters") }

      it "returns not found error" do
        subject

        expect(response).to be_not_found_error("charge")
      end
    end

    context "when subscription has plan override with charge override" do
      let(:overridden_plan) { create(:plan, organization:, parent: plan) }
      let(:subscription) { create(:subscription, customer:, plan: overridden_plan, external_id:) }
      let(:overridden_charge) { create(:standard_charge, plan: overridden_plan, organization:, billable_metric:, parent: charge, code: charge.code) }
      let(:charge_filter) { create(:charge_filter, charge: overridden_charge, organization:) }

      before do
        overridden_charge
      end

      it "returns filters from the overridden charge" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:filters].length).to eq(1)
        expect(json[:filters].first[:lago_id]).to eq(charge_filter.id)
      end
    end

    context "when both parent charge and overridden charge have filters" do
      let(:parent_filter) { create(:charge_filter, charge:, organization:, invoice_display_name: "Parent Filter") }
      let(:overridden_plan) { create(:plan, organization:, parent: plan) }
      let(:subscription) { create(:subscription, customer:, plan: overridden_plan, external_id:) }
      let(:overridden_charge) { create(:standard_charge, plan: overridden_plan, organization:, billable_metric:, parent: charge, code: charge.code) }
      let(:overridden_filter) { create(:charge_filter, charge: overridden_charge, organization:, invoice_display_name: "Override Filter") }

      before do
        create(:charge_filter_value, charge_filter: parent_filter, billable_metric_filter:, values: ["us"], organization:)
        overridden_charge
        create(:charge_filter_value, charge_filter: overridden_filter, billable_metric_filter:, values: ["eu"], organization:)
      end

      it "returns only filters from the overridden charge, not parent" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:filters].length).to eq(1)
        expect(json[:filters].first[:lago_id]).to eq(overridden_filter.id)
        expect(json[:filters].first[:invoice_display_name]).to eq("Override Filter")
        expect(json[:filters].map { |f| f[:lago_id] }).not_to include(parent_filter.id)
      end
    end
  end

  describe "GET /api/v1/subscriptions/:external_id/charges/:code/filters/:id" do
    subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters/#{charge_filter.id}") }

    let(:charge_filter) { create(:charge_filter, charge:, organization:, invoice_display_name: "US Region") }

    before do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["us"], organization:)
    end

    it_behaves_like "requires API permission", "subscription", "read"

    it "returns the charge filter" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:filter][:lago_id]).to eq(charge_filter.id)
      expect(json[:filter][:invoice_display_name]).to eq("US Region")
      expect(json[:filter][:values]).to eq({region: ["us"]})
    end

    context "when subscription does not exist" do
      let(:external_id_query_param) { "invalid_external_id" }

      it "returns not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
      end
    end

    context "when charge does not exist" do
      subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/invalid_code/filters/#{charge_filter.id}") }

      it "returns not found error" do
        subject

        expect(response).to be_not_found_error("charge")
      end
    end

    context "when charge filter does not exist" do
      subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters/#{SecureRandom.uuid}") }

      it "returns not found error" do
        subject

        expect(response).to be_not_found_error("charge_filter")
      end
    end

    context "when subscription has plan override with charge override" do
      let(:overridden_plan) { create(:plan, organization:, parent: plan) }
      let(:subscription) { create(:subscription, customer:, plan: overridden_plan, external_id:) }
      let(:overridden_charge) { create(:standard_charge, plan: overridden_plan, organization:, billable_metric:, parent: charge, code: charge.code) }
      let(:charge_filter) { create(:charge_filter, charge: overridden_charge, organization:, invoice_display_name: "Override Filter") }

      before do
        overridden_charge
      end

      it "returns the filter from the overridden charge" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:filter][:lago_id]).to eq(charge_filter.id)
        expect(json[:filter][:invoice_display_name]).to eq("Override Filter")
        expect(json[:filter][:charge_code]).to eq(overridden_charge.code)
      end
    end
  end

  describe "POST /api/v1/subscriptions/:external_id/charges/:code/filters" do
    subject { post_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters", {filter: create_params}) }

    let(:create_params) do
      {
        invoice_display_name: "US Region Filter",
        properties: {amount: "50"},
        values: {billable_metric_filter.key => ["us"]}
      }
    end

    context "with premium license" do
      around { |test| lago_premium!(&test) }

      it_behaves_like "requires API permission", "subscription", "write"

      it "creates a plan override, charge override, and charge filter" do
        expect { subject }
          .to change(Plan, :count).by(1)
          .and change(Charge, :count).by(1)
          .and change(ChargeFilter, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:filter][:invoice_display_name]).to eq("US Region Filter")
        expect(json[:filter][:properties]).to include(amount: "50")
        expect(json[:filter][:values]).to eq({region: ["us"]})
      end

      it "updates the subscription to use the overridden plan" do
        subject

        subscription.reload
        expect(subscription.plan.parent_id).to eq(plan.id)
      end

      context "when subscription does not exist" do
        let(:external_id_query_param) { "invalid_external_id" }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("subscription")
        end
      end

      context "when charge does not exist" do
        subject { post_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/invalid_code/filters", {filter: create_params}) }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("charge")
        end
      end

      context "when values are missing" do
        let(:create_params) do
          {
            invoice_display_name: "US Region Filter",
            properties: {amount: "50"}
          }
        end

        it "returns validation error" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details]).to include(:values)
        end
      end

      context "when subscription already has plan override with charge override" do
        let(:overridden_plan) { create(:plan, organization:, parent: plan) }
        let(:subscription) { create(:subscription, customer:, plan: overridden_plan, external_id:) }
        let(:overridden_charge) { create(:standard_charge, plan: overridden_plan, organization:, billable_metric:, parent: charge, code: charge.code) }

        before { overridden_charge }

        it "does not create a new plan or charge" do
          expect { subject }
            .to not_change(Plan, :count)
            .and not_change(Charge, :count)
            .and change(ChargeFilter, :count).by(1)
        end

        it "creates the filter on the existing charge override" do
          subject

          expect(response).to have_http_status(:success)
          new_filter = ChargeFilter.find(json[:filter][:lago_id])
          expect(new_filter.charge_id).to eq(overridden_charge.id)
        end
      end

      context "when parent charge has existing filters" do
        let(:parent_filter) { create(:charge_filter, charge:, organization:, invoice_display_name: "Parent Filter") }

        before do
          create(:charge_filter_value, charge_filter: parent_filter, billable_metric_filter:, values: ["eu"], organization:)
        end

        it "creates a new filter without affecting parent filters" do
          expect { subject }
            .to change(Plan, :count).by(1)
            .and change(Charge, :count).by(1)
            .and change(ChargeFilter, :count).by(2) # 1 copied from parent + 1 new

          expect(response).to have_http_status(:success)

          # Parent filter should be unchanged
          expect(parent_filter.reload.invoice_display_name).to eq("Parent Filter")
        end

        it "creates charge override with parent_id pointing to original charge" do
          subject

          subscription.reload
          overridden_charge = subscription.plan.charges.find_by(code: charge.code)
          expect(overridden_charge.parent_id).to eq(charge.id)
        end
      end
    end

    context "without premium license" do
      it "returns forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PUT /api/v1/subscriptions/:external_id/charges/:code/filters/:id" do
    subject { put_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters/#{charge_filter.id}", {filter: update_params}) }

    let(:charge_filter) { create(:charge_filter, charge:, organization:, invoice_display_name: "Original Name", properties: {"amount" => "10"}) }
    let(:update_params) do
      {
        invoice_display_name: "Updated Name",
        properties: {amount: "100"}
      }
    end

    before do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["us"], organization:)
    end

    context "with premium license" do
      around { |test| lago_premium!(&test) }

      it_behaves_like "requires API permission", "subscription", "write"

      it "creates a plan override and charge override, then updates the filter" do
        expect { subject }
          .to change(Plan, :count).by(1)
          .and change(Charge, :count).by(1)
          .and change(ChargeFilter, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:filter][:invoice_display_name]).to eq("Updated Name")
        expect(json[:filter][:properties]).to include(amount: "100")
      end

      it "updates the subscription to use the overridden plan" do
        subject

        subscription.reload
        expect(subscription.plan.parent_id).to eq(plan.id)
      end

      context "when subscription does not exist" do
        let(:external_id_query_param) { "invalid_external_id" }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("subscription")
        end
      end

      context "when charge does not exist" do
        subject { put_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/invalid_code/filters/#{charge_filter.id}", {filter: update_params}) }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("charge")
        end
      end

      context "when charge filter does not exist" do
        subject { put_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters/#{SecureRandom.uuid}", {filter: update_params}) }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("charge_filter")
        end
      end

      context "when subscription already has plan override with charge and filter override" do
        let(:overridden_plan) { create(:plan, organization:, parent: plan) }
        let(:subscription) { create(:subscription, customer:, plan: overridden_plan, external_id:) }
        let(:overridden_charge) { create(:standard_charge, plan: overridden_plan, organization:, billable_metric:, parent: charge, code: charge.code) }
        let(:charge_filter) { create(:charge_filter, charge: overridden_charge, organization:, invoice_display_name: "Original Name", properties: {"amount" => "10"}) }

        before do
          overridden_charge
          create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["us"], organization:)
        end

        it "does not create new plan, charge, or filter" do
          expect { subject }
            .to not_change(Plan, :count)
            .and not_change(Charge, :count)
            .and not_change(ChargeFilter, :count)
        end

        it "updates the existing filter override" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:filter][:lago_id]).to eq(charge_filter.id)
          expect(json[:filter][:invoice_display_name]).to eq("Updated Name")
          expect(json[:filter][:properties]).to include(amount: "100")
        end
      end

      context "when updating filter on parent charge (no override yet)" do
        # charge_filter is on parent charge, subscription uses parent plan (no override)
        # When update is called, it creates plan override, charge override (with copied filters), then updates

        it "does not modify the parent filter" do
          subject

          expect(response).to have_http_status(:success)

          # Parent filter should remain unchanged
          charge_filter.reload
          expect(charge_filter.invoice_display_name).to eq("Original Name")
          expect(charge_filter.properties["amount"]).to eq("10")
        end

        it "creates override chain and updates the copied filter" do
          expect { subject }
            .to change(Plan, :count).by(1)
            .and change(Charge, :count).by(1)
            .and change(ChargeFilter, :count).by(1) # copied filter

          expect(response).to have_http_status(:success)

          # The returned filter should be the copied one with updated properties
          expect(json[:filter][:lago_id]).not_to eq(charge_filter.id)
          expect(json[:filter][:invoice_display_name]).to eq("Updated Name")
          expect(json[:filter][:properties]).to include(amount: "100")
        end

        it "creates charge override with parent_id pointing to original charge" do
          subject

          subscription.reload
          overridden_charge = subscription.plan.charges.find_by(code: charge.code)
          expect(overridden_charge.parent_id).to eq(charge.id)
        end
      end
    end

    context "without premium license" do
      it "returns forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/v1/subscriptions/:external_id/charges/:code/filters/:id" do
    subject { delete_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters/#{charge_filter.id}") }

    let(:charge_filter) { create(:charge_filter, charge:, organization:) }
    let(:charge_filter_value) do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["us"], organization:)
    end

    before { charge_filter_value }

    context "with premium license" do
      around { |test| lago_premium!(&test) }

      it_behaves_like "requires API permission", "subscription", "write"

      it "creates a plan override and charge override, then soft deletes the filter" do
        expect { subject }
          .to change(Plan, :count).by(1)
          .and change(Charge, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:filter][:lago_id]).to be_present
      end

      it "updates the subscription to use the overridden plan" do
        subject

        subscription.reload
        expect(subscription.plan.parent_id).to eq(plan.id)
      end

      context "when subscription does not exist" do
        let(:external_id_query_param) { "invalid_external_id" }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("subscription")
        end
      end

      context "when charge does not exist" do
        subject { delete_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/invalid_code/filters/#{charge_filter.id}") }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("charge")
        end
      end

      context "when charge filter does not exist" do
        subject { delete_with_token(organization, "/api/v1/subscriptions/#{external_id_query_param}/charges/#{charge.code}/filters/#{SecureRandom.uuid}") }

        it "returns not found error" do
          subject

          expect(response).to be_not_found_error("charge_filter")
        end
      end

      context "when subscription already has plan override with charge and filter override" do
        let(:overridden_plan) { create(:plan, organization:, parent: plan) }
        let(:subscription) { create(:subscription, customer:, plan: overridden_plan, external_id:) }
        let(:overridden_charge) { create(:standard_charge, plan: overridden_plan, organization:, billable_metric:, parent: charge, code: charge.code) }
        let(:charge_filter) { create(:charge_filter, charge: overridden_charge, organization:) }
        let(:charge_filter_value) do
          create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["us"], organization:)
        end

        before { overridden_charge }

        it "does not create new plan or charge" do
          expect { subject }
            .to not_change(Plan, :count)
            .and not_change(Charge, :count)
        end

        it "soft deletes the existing filter override" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:filter][:lago_id]).to eq(charge_filter.id)
          expect(charge_filter.reload.deleted_at).to be_present
        end

        it "soft deletes the charge filter values" do
          subject

          expect(charge_filter_value.reload.deleted_at).to be_present
        end
      end

      context "when deleting filter on parent charge (no override yet)" do
        # charge_filter is on parent charge, subscription uses parent plan (no override)
        # When delete is called, it creates plan override, charge override (with copied filters), then deletes

        it "does not delete the parent filter" do
          subject

          expect(response).to have_http_status(:success)

          # Parent filter should remain unchanged (not discarded)
          charge_filter.reload
          expect(charge_filter.deleted_at).to be_nil
          expect(charge_filter_value.reload.deleted_at).to be_nil
        end

        it "creates override chain and deletes the copied filter" do
          # A new filter is created (copied) then soft deleted, so count changes by 1 (default scope excludes deleted)
          expect { subject }
            .to change(Plan, :count).by(1)
            .and change(Charge, :count).by(1)
            .and change(ChargeFilter, :count).by(0) # created and deleted, so net change is 0 in default scope

          expect(response).to have_http_status(:success)

          # The returned filter should be the copied one that was deleted, not the parent
          deleted_filter_id = json[:filter][:lago_id]
          expect(deleted_filter_id).not_to eq(charge_filter.id)

          deleted_filter = ChargeFilter.unscoped.find(deleted_filter_id)
          expect(deleted_filter.deleted_at).to be_present
        end

        it "creates charge override with parent_id pointing to original charge" do
          subject

          subscription.reload
          overridden_charge = subscription.plan.charges.find_by(code: charge.code)
          expect(overridden_charge.parent_id).to eq(charge.id)
        end
      end
    end

    context "without premium license" do
      it "returns forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
