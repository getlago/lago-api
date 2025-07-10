# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SubscriptionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 500, description: "desc") }
  let(:commitment_invoice_display_name) { "Overriden minimum commitment name" }
  let(:commitment_amount_cents) { 1234 }

  around { |test| lago_premium!(&test) }

  describe "POST /api/v1/subscriptions" do
    subject { post_with_token(organization, "/api/v1/subscriptions", body) }

    let(:body) { {subscription: params} }
    let(:subscription_at) { Time.current.iso8601 }
    let(:ending_at) { (Time.current + 1.year).iso8601 }
    let(:plan_code) { plan.code }

    let(:params) do
      {
        external_customer_id: customer.external_id,
        plan_code:,
        name: "subscription name",
        external_id: SecureRandom.uuid,
        billing_time: "anniversary",
        subscription_at:,
        ending_at:,
        plan_overrides: {
          amount_cents: 100,
          name: "overridden name",
          minimum_commitment: {
            invoice_display_name: commitment_invoice_display_name,
            amount_cents: commitment_amount_cents
          },
          usage_thresholds: [
            amount_cents: override_amount_cents,
            threshold_display_name: override_display_name
          ]
        }
      }
    end

    let(:override_amount_cents) { 777 }
    let(:override_display_name) { "Overriden Threshold 12" }

    before { customer }

    include_examples "requires API permission", "subscription", "write"

    it "returns a success", :aggregate_failures do
      create(:plan, code: plan.code, parent_id: plan.id, organization:, description: "foo")

      freeze_time do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:subscription]).to include(
          lago_id: String,
          external_id: String,
          external_customer_id: customer.external_id,
          lago_customer_id: customer.id,
          plan_code: plan.code,
          status: "active",
          name: "subscription name",
          started_at: String,
          billing_time: "anniversary",
          subscription_at: Time.current.iso8601,
          ending_at: (Time.current + 1.year).iso8601,
          previous_plan_code: nil,
          next_plan_code: nil,
          downgrade_plan_date: nil
        )
        expect(json[:subscription][:plan]).to include(
          amount_cents: 100,
          name: "overridden name",
          description: "desc"
        )
        expect(json[:subscription][:plan][:minimum_commitment]).to include(
          invoice_display_name: commitment_invoice_display_name,
          amount_cents: commitment_amount_cents
        )
      end
    end

    it "doesn't create a new customer" do
      expect { subject }.not_to change(Customer, :count)
    end

    context "when progressive billing premium integration is present" do
      around { |test| lago_premium!(&test) }

      before do
        organization.update!(premium_integrations: ["progressive_billing"])
      end

      it "creates subscription with an overriden plan with usage thresholds" do
        subject

        expect(response).to have_http_status(:ok)

        expect(json[:subscription][:plan][:usage_thresholds].first).to include(
          amount_cents: override_amount_cents,
          threshold_display_name: override_display_name
        )
      end
    end

    context "with external_customer_id, external_id and name as integer" do
      let(:params) do
        {
          external_customer_id: 123,
          plan_code:,
          name: 456,
          external_id: 789
        }
      end

      it "returns a success" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:subscription]).to include(
          lago_id: String,
          external_customer_id: "123",
          name: "456",
          external_id: "789"
        )
      end

      it "creates a new customer in the organization default billing entity" do
        expect { subject }.to change(Customer, :count).by(1)

        customer = Customer.find_by(external_id: "123")
        expect(customer.organization).to eq(organization)
        expect(customer.billing_entity).to eq(organization.default_billing_entity)
      end

      context "when passing billing_entity_code" do
        let(:billing_entity) { create(:billing_entity, organization:) }
        let(:params) do
          {
            external_customer_id: 123,
            plan_code:,
            name: 456,
            external_id: 789,
            billing_entity_code: billing_entity.code
          }
        end

        it "creates a new customer with the given billing entity" do
          expect { subject }.to change(Customer, :count).by(1)

          customer = Customer.find_by(external_id: "123")
          expect(customer.billing_entity).to eq(billing_entity)
        end

        context "when billing entity does not exist" do
          let(:params) do
            {
              external_customer_id: 123,
              plan_code:,
              name: 456,
              external_id: 789,
              billing_entity_code: SecureRandom.uuid
            }
          end

          it "returns a not_found error" do
            subject

            expect(response).to have_http_status(:not_found)
            expect(json[:code]).to eq("billing_entity_not_found")
          end
        end

        context "when passing external_id from another billing entity" do
          let(:params) do
            {
              external_customer_id: customer.external_id,
              plan_code:,
              name: 456,
              external_id: 789,
              billing_entity_code: billing_entity.id
            }
          end

          it "uses the customer ignoring billing_entity" do
            expect { subject }.not_to change(Customer, :count)

            customer.reload
            expect(customer.billing_entity).to eq(organization.default_billing_entity)
          end
        end
      end
    end

    context "without external_customer_id", :aggregate_failures do
      let(:params) do
        {
          plan_code:,
          name: "subscription name",
          external_id: SecureRandom.uuid
        }
      end

      it "returns an unprocessable_entity error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details]).to eq({external_customer_id: %w[value_is_mandatory]})
      end
    end

    context "with invalid plan code" do
      let(:plan_code) { "#{plan.code}-invalid" }

      it "returns a not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with invalid subscription_at" do
      let(:subscription_at) { "hello" }

      it "returns an unprocessable_entity error" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with legacy subscription_date" do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code:,
          name: "subscription name",
          external_id: SecureRandom.uuid,
          billing_time: "anniversary",
          subscription_at: subscription_at
        }
      end

      it "returns a success" do
        subject

        expect(response).to have_http_status(:ok)

        expect(json[:subscription][:lago_id]).to be_present
        expect(json[:subscription][:external_id]).to be_present
        expect(json[:subscription][:external_customer_id]).to eq(customer.external_id)
        expect(json[:subscription][:lago_customer_id]).to eq(customer.id)
        expect(json[:subscription][:plan_code]).to eq(plan.code)
        expect(json[:subscription][:status]).to eq("active")
        expect(json[:subscription][:name]).to eq("subscription name")
        expect(json[:subscription][:started_at]).to be_present
        expect(json[:subscription][:billing_time]).to eq("anniversary")
        expect(json[:subscription][:subscription_at]).to eq(Time.zone.parse(subscription_at).iso8601)
        expect(json[:subscription][:previous_plan_code]).to be_nil
        expect(json[:subscription][:next_plan_code]).to be_nil
        expect(json[:subscription][:downgrade_plan_date]).to be_nil
      end
    end

    context "with payment pre-authorization" do
      context "when the feature isn't enabled" do
        let(:body) { {authorization: {}, subscription: params} }

        it "returns a forbidden error" do
          subject

          expect(response).to have_http_status(:forbidden)
          expect(json[:message]).to match(/beta_payment_authorization/)
        end
      end

      context "when the feature is enabled" do
        let(:organization) { create(:organization, premium_integrations: ["beta_payment_authorization"]) }
        let(:body) do
          {
            authorization: {amount_cents: "100", amount_currency: "USD"},
            subscription: params
          }
        end
        let(:customer) { create(:customer, organization:, payment_provider: :stripe, external_id: "cust_12345") }
        let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider: create(:stripe_provider, organization:), payment_method_id: "pm_12345") }
        let(:stripe_pi) do
          {
            id: "pi_12345",
            amount: "100",
            amount_capturable: "100",
            status: "requires_capture"
          }
        end

        before do
          stripe_customer
          stub_request(:post, "https://api.stripe.com/v1/payment_intents").and_return(status: 200, body: stripe_pi.to_json)
        end

        it "returns a success" do
          allow(PaymentProviders::CancelPaymentAuthorizationJob).to receive(:perform_later)

          subject
          expect(json[:authorization]).to include(stripe_pi)
          expect(json[:subscription]).to include(status: "active")

          expect(PaymentProviders::CancelPaymentAuthorizationJob).to have_received(:perform_later).with(
            payment_provider: stripe_customer.payment_provider, id: stripe_pi[:id]
          )
        end

        context "when parameters are incorrect" do
          let(:body) do
            {
              authorization: {amount_cents: "100"},
              subscription: params
            }
          end

          it "returns an error" do
            subject

            expect(response).to have_http_status(:bad_request)
            expect(json[:error]).to eq "BadRequest: param is missing or the value is empty or invalid: amount_currency"
          end
        end

        context "when customer has no payment method" do
          let(:provider_customer_id) { "cus_Rw5Qso78STEap3" }
          let(:stripe_customer) { create(:stripe_customer, customer:, provider_customer_id:, payment_provider: create(:stripe_provider, organization:), payment_method_id: nil) }

          context "when customer has a default payment method on Stripe" do
            it do
              stub_request(:get, %r{/v1/customers/#{provider_customer_id}$}).and_return(
                status: 200, body: get_stripe_fixtures("customer_retrieve_response.json")
              )
              stub_request(:get, %r{/v1/customers/#{provider_customer_id}/payment_methods}).and_return(
                status: 200, body: get_stripe_fixtures("customer_list_payment_methods_empty_response.json")
              )

              subject

              expect(response).to have_http_status(:unprocessable_entity)
              expect(json[:error_details][:payment_method_id]).to include "customer_has_no_payment_method"
            end
          end
        end

        context "when the authorization failed (card declined)" do
          it do
            stripe_card_declined = get_stripe_fixtures("payment_intent_authorization_failed_response.json")
            stub_request(:post, %r{/v1/payment_intents}).and_return(
              status: 402,
              body: stripe_card_declined,
              headers: {"request-id" => "req_R6dwJQCrHDQkZr"}
            )
            subject

            expect(response).to have_http_status(:unprocessable_entity)
            expect(json[:code]).to eq "provider_error"
            expect(json[:provider][:code]).to start_with "stripe_account_"
            expect(json[:error_details]).to include({
              code: "card_declined",
              message: "Your card was declined.",
              request_id: "req_R6dwJQCrHDQkZr",
              http_status: 402
            })
          end
        end
      end
    end
  end

  describe "DELETE /api/v1/subscriptions/:external_id" do
    subject { delete_with_token(organization, "/api/v1/subscriptions/#{external_id}", params) }

    let(:subscription) { create(:subscription, customer:, plan:) }
    let(:external_id) { subscription.external_id }
    let(:params) { {} }

    include_examples "requires API permission", "subscription", "write"

    def test_termination(expected_on_termination_credit_note: nil)
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(json[:subscription][:status]).to eq("terminated")
      expect(json[:subscription][:terminated_at]).to be_present
      expect(json[:subscription][:on_termination_credit_note]).to eq(expected_on_termination_credit_note)
    end

    it "terminates a subscription" do
      test_termination(expected_on_termination_credit_note: nil)
    end

    context "when plan is pay_in_arrears" do
      let(:params) { {on_termination_credit_note: "credit"} }

      it "terminates subscription but ignores on_termination_credit_note" do
        test_termination(expected_on_termination_credit_note: nil)
      end
    end

    context "when plan is pay_in_advance" do
      let(:plan) { create(:plan, :pay_in_advance, organization:) }
      let(:subscription) { create(:subscription, customer:, plan:) }

      context "without on_termination_credit_note parameter" do
        it "terminates subscription with credit note behavior" do
          test_termination(expected_on_termination_credit_note: "credit")
        end
      end

      context "with on_termination_credit_note parameter" do
        [nil, "", "credit"].each do |on_termination_credit_note|
          context "when on_termination_credit_note is #{on_termination_credit_note.inspect}" do
            let(:params) { {on_termination_credit_note:}.compact }

            it "terminates subscription with credit note behavior" do
              test_termination(expected_on_termination_credit_note: "credit")
            end
          end
        end

        context "when on_termination_credit_note is skip" do
          let(:params) { {on_termination_credit_note: "skip"} }

          it "terminates subscription with skip behavior" do
            test_termination(expected_on_termination_credit_note: "skip")
          end
        end

        context "with invalid on_termination_credit_note value" do
          let(:params) { {on_termination_credit_note: "invalid"} }

          it "returns validation error" do
            subject

            expect(response).to have_http_status(:unprocessable_entity)
            expect(json[:error_details]).to include(
              on_termination_credit_note: ["invalid_value"]
            )
          end
        end
      end
    end

    context "when subscription is pending" do
      let(:subscription) { create(:subscription, :pending, customer:, plan:) }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
      end

      context "when status is given" do
        let(:params) { {status: "pending"} }

        it "cancels the subscription" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:subscription][:lago_id]).to eq(subscription.id)
          expect(json[:subscription][:status]).to eq("canceled")
          expect(json[:subscription][:canceled_at]).to be_present
        end
      end
    end

    context "with not existing subscription" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PUT /api/v1/subscriptions/:external_id" do
    subject do
      put_with_token(
        organization,
        "/api/v1/subscriptions/#{external_id}",
        params
      )
    end

    let(:params) { {subscription: update_params} }
    let(:subscription) { create(:subscription, :pending, customer:, plan:) }
    let(:external_id) { subscription.external_id }

    let(:update_params) do
      {
        name: "subscription name new",
        subscription_at: "2022-09-05T12:23:12Z",
        plan_overrides: {
          name: "plan new name",
          minimum_commitment: {
            invoice_display_name: commitment_invoice_display_name,
            amount_cents: 1234
          },
          usage_thresholds: [
            id: usage_threshold.id,
            amount_cents: override_amount_cents,
            threshold_display_name: override_display_name
          ]
        }
      }
    end

    let(:override_amount_cents) { 999 }
    let(:override_display_name) { "Overriden Threshold 1" }
    let(:usage_threshold) { create(:usage_threshold, plan:) }

    before do
      subscription
      usage_threshold
    end

    include_examples "requires API permission", "subscription", "write"

    it "updates a subscription", :aggregate_failures do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(json[:subscription][:name]).to eq("subscription name new")
      expect(json[:subscription][:subscription_at].to_s).to eq("2022-09-05T12:23:12Z")

      expect(json[:subscription][:plan]).to include(
        name: "plan new name"
      )

      expect(json[:subscription][:plan][:minimum_commitment]).to include(
        invoice_display_name: commitment_invoice_display_name,
        amount_cents: commitment_amount_cents
      )
    end

    context "when progressive billing premium integration is present" do
      around { |test| lago_premium!(&test) }

      before do
        organization.update!(premium_integrations: ["progressive_billing"])
      end

      it "updates subscription with an overriden plan with usage thresholds" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:subscription][:plan][:usage_thresholds].first).to include(
          amount_cents: override_amount_cents,
          threshold_display_name: override_display_name
        )
      end
    end

    context "with not existing subscription" do
      let(:external_id) { SecureRandom.uuid }

      it "returns an not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with multuple subscriptions" do
      let(:active_plan) { create(:plan, organization:, amount_cents: 5000, description: "desc") }
      let(:active_subscription) do
        create(:subscription, external_id: subscription.external_id, customer:, plan:)
      end

      before { active_subscription }

      it "updates the active subscription", :aggregate_failures do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription][:lago_id]).to eq(active_subscription.id)
        expect(json[:subscription][:name]).to eq("subscription name new")

        expect(json[:subscription][:plan]).to include(
          name: "plan new name"
        )
      end

      context "with pending params" do
        let(:params) { {subscription: update_params, status: "pending"} }

        it "updates the pending subscription" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:subscription][:lago_id]).to eq(subscription.id)
          expect(json[:subscription][:name]).to eq("subscription name new")
          expect(json[:subscription][:subscription_at].to_s).to eq("2022-09-05T12:23:12Z")

          expect(json[:subscription][:plan]).to include(
            name: "plan new name"
          )
        end
      end
    end
  end

  describe "GET /api/v1/subscriptions/:external_id" do
    subject do
      get_with_token(organization, "/api/v1/subscriptions/#{external_id}", params)
    end

    let(:params) { {} }
    let(:subscription) { create(:subscription, customer:, plan:) }
    let(:external_id) { subscription.external_id }

    include_examples "requires API permission", "subscription", "read"

    it "returns a subscription" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription]).to include(
        lago_id: subscription.id,
        external_id: subscription.external_id
      )
    end

    context "when subscription does not exist" do
      let(:external_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when status is given" do
      let(:params) { {status: "pending"} }

      let!(:matching_subscription) do
        create(:subscription, customer:, plan:, status: :pending, external_id: subscription.external_id)
      end

      it "returns the subscription with the given status" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription]).to include(
          lago_id: matching_subscription.id,
          external_id: matching_subscription.external_id
        )
      end
    end

    context "when there are multiple terminated subscriptions" do
      let(:subscription) do
        create(:subscription, customer:, plan:, status: :terminated, terminated_at: 10.days.ago)
      end

      let(:matching_subscription) do
        create(
          :subscription,
          customer:,
          plan:,
          external_id: subscription.external_id,
          terminated_at: 5.days.ago,
          status: :terminated
        )
      end

      let(:params) { {status: "terminated"} }

      before do
        matching_subscription
      end

      it "returns the latest terminated subscription" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription]).to include(
          lago_id: matching_subscription.id,
          external_id: matching_subscription.external_id
        )
      end
    end
  end

  describe "GET /api/v1/subscriptions" do
    subject { get_with_token(organization, "/api/v1/subscriptions", params) }

    let!(:subscription) { create(:subscription, customer:, plan:) }
    let(:params) { {external_customer_id: external_customer_id} }
    let(:external_customer_id) { customer.external_id }

    include_examples "requires API permission", "subscription", "read"

    it "returns subscriptions" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscriptions].count).to eq(1)
      expect(json[:subscriptions].first[:lago_id]).to eq(subscription.id)
    end

    context "with next and previous subscriptions" do
      let(:previous_subscription) do
        create(
          :subscription,
          customer:,
          plan: create(:plan, organization:),
          status: :terminated
        )
      end

      let(:next_subscription) do
        create(
          :subscription,
          customer:,
          plan: create(:plan, organization:),
          status: :pending
        )
      end

      before do
        subscription.update!(previous_subscription:, next_subscriptions: [next_subscription])
      end

      it "returns next and previous plan code" do
        subject

        subscription = json[:subscriptions].first
        expect(subscription[:previous_plan_code]).to eq(previous_subscription.plan.code)
        expect(subscription[:next_plan_code]).to eq(next_subscription.plan.code)
      end

      it "returns the downgrade plan date" do
        current_date = DateTime.parse("20 Jun 2022")

        travel_to(current_date) do
          subject

          subscription = json[:subscriptions].first
          expect(subscription[:downgrade_plan_date]).to eq("2022-07-01")
        end
      end
    end

    context "with pagination" do
      let(:params) do
        {
          external_customer_id:,
          page: 1,
          per_page: 1
        }
      end

      before do
        another_plan = create(:plan, organization:, amount_cents: 30_000)
        create(:subscription, customer:, plan: another_plan)
      end

      it "returns subscriptions with correct meta data" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:subscriptions].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context "with plan code" do
      let(:params) { {plan_code: plan.code} }

      it "returns subscriptions" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscriptions].count).to eq(1)
        expect(json[:subscriptions].first[:lago_id]).to eq(subscription.id)
      end
    end

    context "with terminated status" do
      let!(:terminated_subscription) do
        create(:subscription, customer:, plan: create(:plan, organization:), status: :terminated)
      end

      let(:params) do
        {
          external_customer_id:,
          status: ["terminated"]
        }
      end

      it "returns terminated subscriptions" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscriptions].count).to eq(1)
        expect(json[:subscriptions].first[:lago_id]).to eq(terminated_subscription.id)
      end
    end
  end
end
