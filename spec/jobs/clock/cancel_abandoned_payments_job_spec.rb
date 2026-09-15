# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::CancelAbandonedPaymentsJob, job: true do
  subject(:job) { described_class }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:abandoned) { build_payment({}) }

  def build_payment(attributes)
    create(:payment, {customer:, organization:, payment_provider: stripe_provider,
                      payable_payment_status: :processing, status: "requires_action",
                      updated_at: 2.days.ago}.merge(attributes))
  end

  before { abandoned }

  it "enqueues a cancellation for the abandoned payment" do
    expect { job.perform_now }
      .to have_enqueued_job(Invoices::Payments::CancelAbandonedJob).with(abandoned)
  end

  context "when the customer was redirected minutes ago" do
    let(:fresh) { build_payment(updated_at: 5.minutes.ago) }

    before { fresh }

    it "leaves it alone until the window passes" do
      expect { job.perform_now }
        .not_to have_enqueued_job(Invoices::Payments::CancelAbandonedJob).with(fresh)
    end
  end

  context "when the payment provider was deleted" do
    let(:orphaned) { build_payment({}) }

    before do
      orphaned
      orphaned.payment_provider.discard!
    end

    it "skips it, since nothing can cancel a payment without a provider" do
      expect { job.perform_now }
        .not_to have_enqueued_job(Invoices::Payments::CancelAbandonedJob).with(orphaned)
    end
  end

  context "when the payment was recorded manually" do
    let(:invoice) { create(:invoice, organization:, customer:, total_amount_cents: 100_000) }
    let(:manual) do
      build_payment(payment_type: :manual, reference: "wire 42", payable: invoice, amount_cents: 1_000)
    end

    before { manual }

    it "skips it, since there is no provider intent to cancel" do
      expect { job.perform_now }
        .not_to have_enqueued_job(Invoices::Payments::CancelAbandonedJob).with(manual)
    end
  end

  context "when the payable is a payment request" do
    let(:payment_request) { create(:payment_request, organization:, customer:) }
    let(:request_payment) { build_payment(payable: payment_request) }

    before { request_payment }

    it "skips it, since this flow only cancels invoice payments" do
      expect { job.perform_now }
        .not_to have_enqueued_job(Invoices::Payments::CancelAbandonedJob).with(request_payment)
    end
  end

  context "with more payments than fit in one batch" do
    let(:second) { build_payment({}) }

    before do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      stub_const("#{described_class}::SPACING", 5.minutes)
      second
    end

    it "delays each batch further than the last, so the work arrives as a trickle" do
      job.perform_now

      schedules = enqueued_jobs
        .select { |enqueued| enqueued["job_class"] == Invoices::Payments::CancelAbandonedJob.name }
        .map { |enqueued| Time.zone.parse(enqueued["scheduled_at"]) }
        .sort

      expect(schedules.last - schedules.first).to be_within(5.seconds).of(5.minutes)
    end
  end
end
