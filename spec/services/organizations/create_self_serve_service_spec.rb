# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::CreateSelfServeService do
  subject(:result) { described_class.call(name:, **options) }

  let(:name) { "  Acme   Corp " }
  let(:options) { {} }

  it "creates a self-serve production organization and its sandbox" do
    production = result.organization
    sandbox = result.sandbox_organization

    expect(production).to have_attributes(name: "Acme Corp", self_serve: true, environment: "production",
      production_organization_id: nil, document_numbering: "per_organization")
    expect(sandbox).to have_attributes(name: "Acme Corp Sandbox", slug: "#{production.slug}-sandbox", self_serve: true,
      environment: "sandbox", production_organization_id: production.id, document_numbering: "per_organization")
    expect(production.reload.sandbox_organization).to eq(sandbox)
  end

  it "gives each organization its own API key and billing entity" do
    production = result.organization
    sandbox = result.sandbox_organization

    expect(production.api_keys.sole.value).not_to eq(sandbox.api_keys.sole.value)
    expect(production.billing_entities.sole).to have_attributes(id: production.id, code: "acme_corp",
      document_numbering: "per_billing_entity")
    expect(sandbox.billing_entities.sole).to have_attributes(id: sandbox.id, code: "acme_corp_sandbox",
      document_numbering: "per_billing_entity")
  end

  it "tracks both billing entities only after commit" do
    expect { result }.to have_enqueued_job_after_commit(SegmentTrackJob).twice
  end

  context "with per_customer numbering" do
    let(:options) { {document_numbering: "per_customer"} }

    it "numbers both organizations per customer" do
      expect([result.organization, result.sandbox_organization].map(&:document_numbering))
        .to eq(%w[per_customer per_customer])
      expect([result.organization, result.sandbox_organization].map { it.billing_entities.sole.document_numbering })
        .to eq(%w[per_customer per_customer])
    end
  end

  context "with an unknown numbering" do
    let(:options) { {document_numbering: "bogus"} }

    it "creates nothing" do
      expect { result }.not_to change(Organization, :count)
      expect(result.error.messages).to eq(document_numbering: ["value_is_invalid"])
    end
  end

  context "with premium settings", :premium do
    let(:feature_flag) { FeatureFlag::DEFINITION.keys.first }
    let(:options) { {timezone: "Europe/Paris", premium_integrations: ["okta"], feature_flags: [feature_flag]} }

    it "gives the sandbox the same settings" do
      settings = [result.organization, result.sandbox_organization]
        .map(&:reload).map { [it.timezone, it.default_currency, it.premium_integrations, it.feature_flags] }

      expect(settings).to eq([["Europe/Paris", "USD", ["okta"], [feature_flag]]] * 2)
    end
  end

  context "with an unknown feature flag" do
    let(:options) { {feature_flags: ["no_such_flag"]} }

    it "creates nothing" do
      expect { result }.not_to change(Organization, :count)
      expect(result.error.messages).to eq(feature_flags: ["value_is_invalid"])
    end
  end

  {"" => "value_is_mandatory", "a" * 101 => "value_is_too_long", "acme.com" => "value_contains_link"}.each do |bad_name, code|
    context "with the name #{bad_name.first(10).inspect}" do
      let(:name) { bad_name }

      it "returns the name failure and creates nothing" do
        expect { result }.not_to change { [Organization.count, ApiKey.count, BillingEntity.count] }
        expect(result.error.messages).to eq(name: [code])
      end
    end
  end

  context "with a 100-character name" do
    let(:name) { "a" * 100 }

    it "does not cut the sandbox name" do
      expect(result.sandbox_organization.name.length).to eq(108)
    end
  end

  describe "sandbox slug" do
    let(:name) { "Acme" }

    def create_with_slug(slug)
      allow(Organization).to receive(:new).and_wrap_original do |original, attributes|
        original.call(attributes.key?(:slug) ? attributes : attributes.merge(slug:))
      end
      result
    end

    it "keeps 32 characters of a long production slug" do
      slug = "a" * 40

      expect(create_with_slug(slug).sandbox_organization.slug).to eq("#{"a" * 32}-sandbox")
    end

    it "drops a dash left at the end of the cut" do
      slug = "#{"a" * 31}-bcdefgh"

      expect(create_with_slug(slug).sandbox_organization.slug).to eq("#{"a" * 31}-sandbox")
    end

    it "adds a random suffix when the slug is taken" do
      create(:organization, slug: "acme-corp-sandbox")

      expect(create_with_slug("acme-corp").sandbox_organization.slug).to match(/\Aacme-corp-sandbox-[a-z0-9]{3}\z/)
    end
  end

  context "when the sandbox cannot be created" do
    before do
      allow(Organizations::CreateService).to receive(:call!).and_wrap_original do |original, **params|
        if params[:environment] == "sandbox"
          raise BaseResult.new.validation_failure!(errors: {name: ["value_is_invalid"]}).error
        end

        original.call(**params)
      end
    end

    it "rolls the production organization back" do
      expect { result }.not_to change { [Organization.count, ApiKey.count, BillingEntity.count] }
      expect(result.error.messages).to eq(name: ["value_is_invalid"])
    end
  end
end
