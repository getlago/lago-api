# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoint do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:webhooks).dependent(:delete_all) }

  it { is_expected.to validate_presence_of(:webhook_url) }

  describe "validations" do
    subject(:webhook_endpoint) { build(:webhook_endpoint) }

    describe "of webhook url uniqueness" do
      let(:errors) { webhook_endpoint.errors }

      context "when it is unique in scope of organization" do
        it "does not add an error" do
          expect(errors.where(:webhook_url, :taken)).not_to be_present
        end
      end

      context "when it not is unique in scope of organization" do
        subject(:webhook_endpoint) do
          build(:webhook_endpoint, organization:, webhook_url: organization.webhook_endpoints.first.webhook_url)
        end

        let(:organization) { create(:organization) }
        let(:errors) { webhook_endpoint.errors }

        before { webhook_endpoint.valid? }

        it "adds an error" do
          expect(errors.where(:webhook_url, :taken)).to be_present
        end
      end
    end

    context "when http webhook url is valid" do
      before { webhook_endpoint.webhook_url = "http://foo.bar" }

      it "is valid" do
        expect(webhook_endpoint).to be_valid
      end
    end

    context "when https webhook url is valid" do
      before { webhook_endpoint.webhook_url = "https://foo.bar" }

      it "is valid" do
        expect(webhook_endpoint).to be_valid
      end
    end

    context "when webhook url is invalid" do
      before { webhook_endpoint.webhook_url = "foobar" }

      it "is invalid" do
        expect(webhook_endpoint).not_to be_valid
      end
    end
  end
end
