# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiKeys::DestroyService do
  describe "#call" do
    subject(:service_result) { described_class.call(api_key) }

    context "when API key is missing" do
      let(:api_key) { nil }

      it "returns an error" do
        aggregate_failures do
          expect(service_result).not_to be_success
          expect(service_result.error).to be_a(BaseService::NotFoundFailure)
          expect(service_result.error.error_code).to eq("api_key_not_found")
        end
      end

      it "does not send an API key destroyed email" do
        expect { service_result }.not_to have_enqueued_mail(ApiKeyMailer, :destroyed)
      end
    end

    context "when API key is present" do
      let!(:api_key) { create(:api_key) }

      context "when organization has another non-expiring key" do
        before do
          create(:api_key, organization: api_key.organization)
          freeze_time
        end

        it "expires the API key with current time" do
          expect { subject }.to change(api_key, :expires_at).to(Time.current)
        end

        it "sends an API key destroyed email" do
          expect { service_result }
            .to have_enqueued_mail(ApiKeyMailer, :destroyed).with hash_including(params: {api_key:})
        end
      end

      context "when organization has no another non-expiring key" do
        before { create(:api_key, :expired, organization: api_key.organization) }

        it "returns an error" do
          aggregate_failures do
            expect(service_result).not_to be_success
            expect(service_result.error).to be_a(BaseService::ValidationFailure)
            expect(service_result.error.messages.values.flatten).to include("last_non_expiring_api_key")
          end
        end

        it "does not expire the key" do
          expect { subject }.not_to change(api_key, :expires_at).from(nil)
        end

        it "does not send an API key destroyed email" do
          expect { service_result }.not_to have_enqueued_mail(ApiKeyMailer, :destroyed)
        end
      end
    end
  end
end
