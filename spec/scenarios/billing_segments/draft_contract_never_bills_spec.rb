# frozen_string_literal: true

require "rails_helper"

# A draft holds its pricing while it is prepared: nothing bills it, whatever its start date, until it
# is published. Publishing late then catches up the elapsed fixed periods and replays the usage billed
# in advance that arrived while it was a draft.
describe "A draft contract never bills until it is published" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "draft-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "draft-contract") }
  let(:started_at) { Time.zone.parse("2027-01-01 00:00:00") }

  around do |example|
    # The catalog is set up before the contract starts: a rate cannot start in the past.
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "draft-customer", timezone: "UTC", currency: "USD"})
    create_metric({name: "Draft usage", code: "draft-usage", aggregation_type: "sum_agg", field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {name: "Platform", code: "draft-platform", product_type: "fixed"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Usage", code: "draft-usage-product", product_type: "metered", billable_metric_code: "draft-usage"
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Platform", code: "draft-platform-card", product_code: "draft-platform", currency: "USD",
        billing_timing: "advance", proration: false,
        rates: [{
          code: "draft-platform-rate", effective_from: started_at.iso8601, rate_model: "standard",
          billing_interval_unit: "month", rate_properties: {amount: "100"}
        }]
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Usage", code: "draft-usage-card", product_code: "draft-usage-product", currency: "USD",
        billing_timing: "advance", proration: false, display_on_invoice: false, regroup_paid_fees: "invoice",
        rates: [{
          code: "draft-usage-rate", effective_from: started_at.iso8601, rate_model: "standard",
          billing_interval_unit: "month", rate_properties: {amount: "1"}
        }]
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Draft plan", code: "draft-plan", currency: "USD"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans/draft-plan/applied_rate_cards", {applied_rate_card: {rate_card_code: "draft-platform-card", units: 1}})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans/draft-plan/applied_rate_cards", {applied_rate_card: {rate_card_code: "draft-usage-card"}})
    end

    # The draft is prepared after its start date, which no longer matters until it is published.
    travel_to(Time.zone.parse("2027-01-20 10:00:00")) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "draft-contract", code: "default", external_customer_id: "draft-customer",
          plan_code: "draft-plan", status: "draft", started_at: started_at.iso8601
        }})
      end

      create_event({
        external_contract_id: "draft-contract", code: "draft-usage",
        timestamp: Time.current.utc.strftime("%s.%6N"), properties: {"quantity" => 40}
      })
    end

    # Past the end of the first period, so every clock would have billed an active contract by now.
    travel_to(Time.zone.parse("2027-02-02 10:00:00")) do
      run_clocks
    end
  end

  def run_clocks
    perform_enqueued_jobs do
      Clock::ActivateContractsJob.perform_now
      Clock::ScheduleBillingOperationsJob.perform_now
      Clock::ProcessBillingOperationsJob.perform_now
    end
  end

  it "creates no billing operation, fee or invoice while it is a draft" do
    expect(contract).to be_draft
    expect(BillingOperation.where(customer:)).to be_empty
    expect(Fee.where(contract:)).to be_empty
    expect(Invoice.where(customer:)).to be_empty
  end

  context "when it is published after its first period ended" do
    before do
      travel_to(Time.zone.parse("2027-02-02 11:00:00")) do
        api_call { post_with_token(organization, "/api/v2/contracts/draft-contract/publish") }
      end
      # The next clock tick schedules and bills the periods that elapsed while it was a draft.
      travel_to(Time.zone.parse("2027-02-02 12:00:00")) { run_clocks }
    end

    it "bills the elapsed fixed periods and the usage received in advance while it was a draft" do
      expect(contract.reload).to be_active

      usage_fee = Fee.where(contract:).where.not(pay_in_advance_event_transaction_id: nil).sole
      expect(usage_fee).to have_attributes(units: 40, amount_cents: 4_000) # 40 units at $1, sent on January 20
      expect(Fee.where(contract:, fee_type: :product).where.not(id: usage_fee.id).map(&:amount_cents))
        .to eq([10_000, 10_000]) # January and February, $100 each
    end

    it "bills the draft usage once when the replay runs again" do
      replay = -> { Contracts::ReplayDraftUsageJob.perform_now(contract, Time.zone.parse("2027-02-02 11:00:00")) }

      expect { perform_enqueued_jobs(&replay) }.not_to change(Fee, :count)
    end
  end
end
