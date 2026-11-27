# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Quickbooks::CreateService do
  include_context "with mocked security logger"

  let(:organization) { create_default(:organization) }

  describe "#call" do
    subject(:service_call) { described_class.call(params: create_args) }

    let(:name) { "QuickBooks 1" }
    let(:code) { "quickbooks1" }
    let(:connection_id) { "quickbooks-test-connection" }
    let(:provider_config_key) { "quickbooks" }
    let(:connection_url) do
      "https://api.nango.dev/connection/#{connection_id}?provider_config_key=#{provider_config_key}"
    end
    let(:response_status) { 200 }
    let(:realm_id) { "1234567890" }
    let(:response_body) do
      {
        "connection_config" => {"realmId" => realm_id},
        "credentials" => {"access_token" => "fake-access-token"}
      }.to_json
    end

    let(:create_args) do
      {
        name:,
        code:,
        organization_id: organization.id,
        connection_id:,
        sync_invoices: true,
        sync_credit_notes: "true",
        sync_payments: false
      }
    end

    before do
      stub_request(:get, connection_url)
        .to_return(status: response_status, body: response_body, headers: {"Content-Type" => "application/json"})
    end

    shared_examples "a refused creation" do
      it "does not create an integration" do
        expect { service_call }.not_to change(Integrations::QuickbooksIntegration, :count)
      end

      it "does not enqueue a sync job" do
        expect { service_call }.not_to have_enqueued_job(Integrations::Aggregator::PerformSyncJob)
      end
    end

    context "without premium license" do
      it_behaves_like "a refused creation"

      it "returns an error" do
        result = service_call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("premium_integration_missing")
      end
    end

    context "with premium license", :premium do
      context "when quickbooks premium integration is not present" do
        it_behaves_like "a refused creation"

        it "returns an error without calling Nango" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("premium_integration_missing")
          expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
        end
      end

      context "when quickbooks premium integration is present" do
        before do
          organization.update!(premium_integrations: ["quickbooks"])
        end

        context "without validation errors" do
          it "creates an integration with the realm id from Nango" do
            expect { service_call }.to change(Integrations::QuickbooksIntegration, :count).by(1)

            integration = Integrations::QuickbooksIntegration.order(:created_at).last
            expect(integration.name).to eq(name)
            expect(integration.code).to eq(code)
            expect(integration.realm_id).to eq("1234567890")
            expect(integration.settings["sandbox"]).to be(false)
            expect(integration.sync_invoices).to be(true)
            expect(integration.sync_credit_notes).to be(true)
            expect(integration.sync_payments).to be(false)
            expect(integration.connection_id).to eq(connection_id)
            expect(integration.settings).not_to have_key("connection_id")
            expect(integration.secrets_json).to eq({"connection_id" => connection_id})
            expect(integration.ciphertext_for(:secrets)).not_to include(connection_id)
            expect(integration.settings.keys).to match_array(%w[realm_id sandbox sync_invoices sync_credit_notes sync_payments])
            expect(WebMock).to have_requested(:get, connection_url).once
          end

          it "returns the integration in the result object" do
            result = service_call

            expect(result).to be_success
            expect(result.integration).to be_a(Integrations::QuickbooksIntegration)
            expect(result.integration).to be_persisted
          end

          it "calls Integrations::Aggregator::PerformSyncJob" do
            freeze_time do
              expect { service_call }.to have_enqueued_job(Integrations::Aggregator::PerformSyncJob)
                .with(integration: an_instance_of(Integrations::QuickbooksIntegration))
                .at(2.seconds.from_now)
            end
          end

          it_behaves_like "produces a security log", "integration.created" do
            before { service_call }
          end

          it_behaves_like "refused on a shadow organization", Integrations::QuickbooksIntegration
        end

        context "when the sync flags are omitted" do
          let(:create_args) { {name:, code:, organization_id: organization.id, connection_id:} }

          it "stores them as false" do
            service_call

            settings = Integrations::QuickbooksIntegration.order(:created_at).last.settings
            expect(settings["sync_invoices"]).to be(false)
            expect(settings["sync_credit_notes"]).to be(false)
            expect(settings["sync_payments"]).to be(false)
            expect(settings["sandbox"]).to be(false)
          end
        end

        context "when sandbox is nil" do
          let(:create_args) { super().merge(sandbox: nil) }

          it "uses the quickbooks provider config and stores false" do
            result = service_call

            expect(result).to be_success
            expect(result.integration.settings["sandbox"]).to be(false)
            expect(WebMock).to have_requested(:get, connection_url).once
          end
        end

        [true, "true"].each do |sandbox|
          context "when sandbox is #{sandbox.inspect}" do
            let(:create_args) { super().merge(sandbox:) }
            let(:provider_config_key) { "quickbooks-sandbox" }

            it "uses the quickbooks-sandbox provider config and stores true" do
              result = service_call

              expect(result).to be_success
              expect(result.integration.settings["sandbox"]).to be(true)
              expect(result.integration.realm_id).to eq("1234567890")
              expect(WebMock).to have_requested(:get, connection_url).once
            end
          end
        end

        [false, "false"].each do |sandbox|
          context "when sandbox is #{sandbox.inspect}" do
            let(:create_args) { super().merge(sandbox:) }

            it "uses the quickbooks provider config and stores false" do
              result = service_call

              expect(result).to be_success
              expect(result.integration.settings["sandbox"]).to be(false)
              expect(WebMock).to have_requested(:get, connection_url).once
            end
          end
        end

        context 'when sync_invoices is "false"' do
          let(:create_args) { super().merge(sync_invoices: "false") }

          it "stores false" do
            result = service_call

            expect(result).to be_success
            expect(result.integration.sync_invoices).to be(false)
          end
        end

        {404 => "connection_not_found", 500 => "connection_lookup_failed"}.each do |status, error_code|
          context "when Nango answers #{status}" do
            let(:response_status) { status }
            let(:response_body) { {"error" => "fake-nango-error-body"}.to_json }

            it_behaves_like "a refused creation"

            it "returns a third party failure without the Nango body" do
              result = service_call

              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ThirdPartyFailure)
              expect(result.error.third_party).to eq("Nango")
              expect(result.error.error_code).to eq(error_code)
              expect(result.error.message).not_to include("fake-nango-error-body")
              expect(result.integration).to be_nil
            end

            it "does not produce a security log" do
              service_call

              expect(security_logger).not_to have_received(:produce)
            end
          end
        end

        context "when Nango returns no realm id" do
          let(:response_body) { {"connection_config" => {"realmId" => ""}}.to_json }

          it_behaves_like "a refused creation"

          it "returns a third party failure" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ThirdPartyFailure)
            expect(result.error.error_code).to eq("realm_id_missing")
            expect(result.integration).to be_nil
          end
        end

        context "when the realm id is already used in the organization" do
          before do
            create(:quickbooks_integration, organization:, code: "quickbooks_existing", settings: {realm_id:})
          end

          it_behaves_like "a refused creation"

          it "returns a validation failure on realm_id" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages).to eq({realm_id: ["value_already_exist"]})
          end
        end

        context "when a concurrent create stores a conflicting row after the validations passed" do
          # The row lands between the validations of save! and the insert, as in a real race, so only
          # the unique index can refuse it. It is saved without validations, as the other request was.
          def insert_conflicting_row(code:, realm_id:)
            build(:quickbooks_integration, organization:, name: "Concurrent QuickBooks", code:, settings: {realm_id:})
              .save!(validate: false)
          end

          before do
            conflict = conflicting_row
            wrapped = false
            allow(Integrations::QuickbooksIntegration).to receive(:new).and_wrap_original do |original, *args, **kwargs|
              integration = original.call(*args, **kwargs)
              next integration if wrapped

              # Only the service's own record races; the conflicting row is saved as is.
              wrapped = true
              allow(integration).to receive(:save!).and_wrap_original do |save, *save_args, **options|
                integration.validate!
                insert_conflicting_row(**conflict)
                save.call(*save_args, **options, validate: false)
              end
              integration
            end
          end

          context "with the same company" do
            let(:conflicting_row) { {code: "quickbooks_concurrent", realm_id:} }

            it "returns a validation failure on realm_id from the unique index" do
              result = service_call

              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages).to eq({realm_id: ["value_already_exist"]})
              expect(Integrations::QuickbooksIntegration.where(organization:).count).to eq(1)
            end

            it "does not enqueue a sync job" do
              expect { service_call }.not_to have_enqueued_job(Integrations::Aggregator::PerformSyncJob)
            end
          end

          context "with the same code" do
            let(:conflicting_row) { {code:, realm_id: "9999999999"} }

            it "returns a validation failure on code from the unique index" do
              result = service_call

              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages).to eq({code: ["value_already_exist"]})
              expect(Integrations::QuickbooksIntegration.where(organization:).count).to eq(1)
            end

            it "does not enqueue a sync job" do
              expect { service_call }.not_to have_enqueued_job(Integrations::Aggregator::PerformSyncJob)
            end
          end
        end

        context "when the realm id is used in another organization" do
          before do
            create(:quickbooks_integration, organization: create(:organization), code:, settings: {realm_id:})
          end

          it "creates the integration" do
            result = nil
            expect { result = service_call }.to change(Integrations::QuickbooksIntegration, :count).by(1)

            expect(result).to be_success
            expect(result.integration.organization).to eq(organization)
            expect(result.integration.realm_id).to eq(realm_id)
          end
        end

        context "with a blank connection_id" do
          let(:connection_id) { "" }

          it_behaves_like "a refused creation"

          it "returns a validation error without calling Nango" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:connection_id]).to eq(["value_is_mandatory"])
            expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
          end
        end

        context "with a blank name" do
          let(:name) { nil }

          it_behaves_like "a refused creation"

          it "returns a validation error without calling Nango" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
            expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
          end
        end

        context "with a code already used in the organization" do
          before do
            create(:quickbooks_integration, organization:, code:, settings: {realm_id: "9999999999"})
          end

          it_behaves_like "a refused creation"

          it "returns a validation error without calling Nango" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:code]).to eq(["value_already_exist"])
            expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
          end
        end
      end
    end
  end
end
