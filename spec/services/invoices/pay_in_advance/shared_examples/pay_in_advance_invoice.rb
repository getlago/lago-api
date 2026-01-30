# frozen_string_literal: true

RSpec.shared_context "with pay_in_advance_invoice_setup" do
  let(:timestamp) { Time.zone.now.beginning_of_month }
  let(:organization) { create(:organization) }
  let(:billing_entity) { customer.billing_entity }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:email_settings) { ["invoice.finalized", "credit_note.created"] }

  before do
    create(:tax, :applied_to_billing_entity, organization:)
    billing_entity.update!(email_settings:)
  end
end

RSpec.shared_examples "pay_in_advance_invoice_post_creation" do
  before do
    allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
  end

  it "creates InvoiceSubscription object" do
    expect { service_call }.to change(InvoiceSubscription, :count).by(1)
  end

  it "calls SegmentTrackJob" do
    invoice = service_call.invoice

    expect(SegmentTrackJob).to have_been_enqueued.with(
      membership_id: CurrentContext.membership,
      event: "invoice_created",
      properties: {
        organization_id: invoice.organization.id,
        invoice_id: invoice.id,
        invoice_type: invoice.invoice_type
      }
    )
  end

  it "creates a payment" do
    allow(Invoices::Payments::CreateService).to receive(:call_async)

    service_call

    expect(Invoices::Payments::CreateService).to have_received(:call_async)
  end

  it "enqueues a SendWebhookJob for the invoice" do
    expect { service_call }.to have_enqueued_job(SendWebhookJob).with("invoice.created", Invoice)
  end

  it "enqueues a SendWebhookJob for the fees" do
    expect { service_call }.to have_enqueued_job(SendWebhookJob).with("fee.created", Fee)
  end

  it "produces an activity log" do
    invoice = service_call.invoice

    expect(Utils::ActivityLog).to have_produced("invoice.created").with(invoice)
  end

  it "enqueues GenerateDocumentsJob with email false" do
    expect { service_call }.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
  end
end

RSpec.shared_examples "pay_in_advance_premium_email_settings" do
  context "with lago_premium" do
    around { |test| lago_premium!(&test) }

    it "enqueues GenerateDocumentsJob with email true" do
      expect { service_call }.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: true))
    end

    context "when organization does not have right email settings" do
      let(:email_settings) { [] }

      it "enqueues GenerateDocumentsJob with email false" do
        expect { service_call }.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
      end
    end
  end
end

RSpec.shared_examples "pay_in_advance_customer_timezone" do
  context "with customer timezone" do
    let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
    let(:timestamp) { DateTime.parse("2022-11-25 01:00:00") }

    it "assigns the issuing date in the customer timezone" do
      result = service_call

      expect(result.invoice.issuing_date.to_s).to eq("2022-11-24")
      expect(result.invoice.payment_due_date.to_s).to eq("2022-11-24")
    end
  end
end

RSpec.shared_examples "pay_in_advance_grace_period" do
  context "with grace period" do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
    let(:timestamp) { DateTime.parse("2022-11-25 08:00:00") }

    it "assigns the correct issuing date" do
      result = service_call

      expect(result.invoice.issuing_date.to_s).to eq("2022-11-25")
    end
  end
end

RSpec.shared_examples "pay_in_advance_error_handling" do
  context "when an error occurs" do
    context "with a stale object error" do
      before { create(:wallet, customer:, balance_cents: 100) }

      it "propagates the error" do
        allow(Credits::AppliedPrepaidCreditsService)
          .to receive(:call!)
          .and_raise(ActiveRecord::StaleObjectError)

        expect { service_call }.to raise_error(ActiveRecord::StaleObjectError)
      end
    end

    context "with a sequence error" do
      it "propagates the error" do
        allow_any_instance_of(Invoice) # rubocop:disable RSpec/AnyInstance
          .to receive(:save!).and_raise(Sequenced::SequenceError)

        expect { service_call }.to raise_error(Sequenced::SequenceError)
      end
    end
  end
end

RSpec.shared_examples "pay_in_advance_concurrent_lock" do |service_class|
  context "when there is a concurrent lock", transaction: false do
    let(:lock_released_after) { 0.1.seconds }

    before do
      stub_const("#{service_class}::ACQUIRE_LOCK_TIMEOUT", 0.5.seconds)
    end

    around do |test|
      customer_id = customer.id
      queue = Queue.new
      thread = start_lock_thread(queue, customer_id)
      test.run
    ensure
      stop_thread(thread, queue) if thread
    end

    def start_lock_thread(queue, customer_id)
      Thread.start do
        start_time = Time.zone.now
        ApplicationRecord.transaction do
          ApplicationRecord.with_advisory_lock!("customer-#{customer_id}", transaction: true) do
            until queue.size > 0 || Time.zone.now - start_time > lock_released_after
              sleep 0.01
            end
          end
        end
      end
    end

    def stop_thread(thread, queue)
      queue.push(true)
      thread.join
    end

    context "when it fails to acquire the lock" do
      let(:lock_released_after) { 2.seconds }

      it "raises a WithAdvisoryLock::FailedToAcquireLock error" do
        expect { service_call }.to raise_error(WithAdvisoryLock::FailedToAcquireLock)

        expect(customer.invoices.count).to eq(0)
      end
    end

    context "when the lock is acquired" do
      it "creates the invoice" do
        expect { service_call }.to change(Invoice, :count).by(1)
      end
    end
  end
end

RSpec.shared_examples "pay_in_advance_integration_sync" do
  context "when there is integration sync enabled" do
    before do
      allow_any_instance_of(Invoice).to receive(:should_sync_invoice?).and_return(true) # rubocop:disable RSpec/AnyInstance
    end

    it "enqueues the aggregator invoice creation job" do
      expect { service_call }.to have_enqueued_job(Integrations::Aggregator::Invoices::CreateJob)
    end
  end

  context "when there is hubspot integration sync enabled" do
    before do
      allow_any_instance_of(Invoice).to receive(:should_sync_hubspot_invoice?).and_return(true) # rubocop:disable RSpec/AnyInstance
    end

    it "enqueues the hubspot invoice creation job" do
      expect { service_call }.to have_enqueued_job(Integrations::Aggregator::Invoices::Hubspot::CreateJob)
    end
  end
end
