# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConcurrencyThrottlable do
  context "when included in a job" do
    let(:job_class) do
      Class.new(ApplicationJob) do
        include ConcurrencyThrottlable

        def perform
        end
      end
    end

    before { stub_const("ConcurrencyThrottlableTestJob", job_class) }

    it "includes the next window throttling retry" do
      expect(job_class).to include(NextWindowThrottlingRetryable)
    end
  end

  context "when an integration job calls a rate limited provider" do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:customer) { create(:customer, organization:) }
    let_it_be(:integration) { create(:netsuite_integration, organization:) }

    shared_examples "an integration job with both throttling retries" do
      before { allow(service_class).to receive(:call).and_raise(error) }

      context "when the provider is rate limited until its next window" do
        let(:error) { BaseService::NextWindowThrottlingError.new(provider_name: :quickbooks) }
        let(:retry_at) { ActiveJob::Base.queue_adapter.enqueued_jobs.last[:at] }

        it "schedules the next attempt 60 to 90 seconds later" do
          freeze_time do
            job_class.perform_now(**job_arguments)

            expect(retry_at).to be_between(60.seconds.from_now.to_f, 90.seconds.from_now.to_f)
          end
        end
      end

      context "when the provider raises the regular throttling error" do
        let(:error) { BaseService::ThrottlingError.new(provider_name: :xero) }

        it "keeps its own retry rule and gives up after 25 attempts" do
          assert_performed_jobs(25, only: [job_class]) do
            expect { job_class.perform_later(**job_arguments) }.to raise_error(BaseService::ThrottlingError)
          end
        end
      end
    end

    context "with the integration customer create job" do
      let(:job_class) { IntegrationCustomers::CreateJob }
      let(:service_class) { IntegrationCustomers::CreateService }
      let(:job_arguments) { {integration_customer_params: {sync_with_provider: true}, integration:, customer:} }

      it_behaves_like "an integration job with both throttling retries"
    end

    context "with the integration customer update job" do
      let(:job_class) { IntegrationCustomers::UpdateJob }
      let(:service_class) { IntegrationCustomers::UpdateService }
      let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
      let(:job_arguments) do
        {integration_customer_params: {sync_with_provider: true}, integration:, integration_customer:}
      end

      it_behaves_like "an integration job with both throttling retries"
    end

    context "with the invoice create job" do
      let(:job_class) { Integrations::Aggregator::Invoices::CreateJob }
      let(:service_class) { Integrations::Aggregator::Invoices::CreateService }
      let(:job_arguments) { {invoice: create(:invoice, customer:, organization:)} }

      # NOTE: The job looks the invoice up upstream before every retry.
      before do
        allow(Integrations::Aggregator::Invoices::ReconcileService).to receive(:call)
          .and_return(Integrations::Aggregator::Invoices::ReconcileService::Result.new)
      end

      it_behaves_like "an integration job with both throttling retries"
    end

    context "with the credit note create job" do
      let(:job_class) { Integrations::Aggregator::CreditNotes::CreateJob }
      let(:service_class) { Integrations::Aggregator::CreditNotes::CreateService }
      let(:job_arguments) { {credit_note: create(:credit_note, customer:, organization:)} }

      it_behaves_like "an integration job with both throttling retries"
    end

    context "with the payment create job" do
      let(:job_class) { Integrations::Aggregator::Payments::CreateJob }
      let(:service_class) { Integrations::Aggregator::Payments::CreateService }
      let(:job_arguments) { {payment: create(:payment, organization:, customer:)} }

      it_behaves_like "an integration job with both throttling retries"
    end
  end
end
