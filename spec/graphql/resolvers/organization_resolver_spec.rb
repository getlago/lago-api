# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::OrganizationResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:query) do
    <<~GQL
      query {
        organization {
          id
          name
          email
          city
        }
      }
    GQL
  end
  let(:organization) { membership.organization }

  let_it_be(:membership) { create_default(:membership) }

  it "returns the current organization" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {}
    )

    data = result["data"]["organization"]

    expect(data["id"]).to eq(organization.id)
    expect(data["name"]).to eq(organization.name)
    expect(data["email"]).to eq(organization.email)
    expect(data["city"]).to eq(organization.city)
  end

  context "when the default billing entity's term differs from the organization column" do
    let(:query) do
      <<~GQL
        query {
          organization {
            netPaymentTerm
          }
        }
      GQL
    end

    let(:membership) { create(:membership, organization: create(:organization)) }

    before do
      organization.update!(net_payment_term: 30)
      organization.default_billing_entity.update!(payment_term: {"term_type" => "end_of_month"}, net_payment_term: nil)
    end

    it "returns the default billing entity's net_payment_term" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {}
      )

      expect(result["data"]["organization"]["netPaymentTerm"]).to be_nil
    end
  end

  context "when the organization still stores the removed standard_webhooks_signature flag" do
    let(:query) do
      <<~GQL
        query {
          organization {
            featureFlags
          }
        }
      GQL
    end

    let(:membership) { create(:membership, organization: create(:organization, feature_flags: ["standard_webhooks_signature"])) }

    it "returns the feature flags without it" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {}
      )

      expect(result["errors"]).to be_nil
      expect(result["data"]["organization"]["featureFlags"]).to eq([])
    end
  end

  context "with field requiring permissions" do
    let(:query) do
      <<~GQL
        query {
          organization {
            taxIdentificationNumber
            apiKey
            webhookUrl
            billingConfiguration { invoiceFooter }
            emailSettings
            taxes { id code }
          }
        }
      GQL
    end

    it "returns the current organization" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: Permission.permissions_hash(:admin),
        query:,
        variables: {}
      )

      data = result["data"]["organization"]

      expect(data["taxIdentificationNumber"]).to eq(organization.tax_identification_number)
      expect(data["apiKey"]).to eq(organization.api_keys.first.value)
      expect(data["webhookUrl"]).to eq(organization.webhook_endpoints.first.webhook_url)
      expect(data["billingConfiguration"]["invoiceFooter"]).to eq(organization.invoice_footer)
      expect(data["emailSettings"]).to eq(organization.email_settings.map { it.tr(".", "_") })
      expect(data["taxes"]).to eq []
    end
  end
end
