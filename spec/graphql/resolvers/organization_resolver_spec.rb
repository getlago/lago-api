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

  context "with a production organization and its sandbox" do
    let(:query) do
      <<~GQL
        query {
          organization {
            selfServe environment
            productionOrganization { id name slug }
            sandboxOrganization { id name slug }
          }
        }
      GQL
    end

    let(:user) { create(:user) }
    let(:production) { create(:organization, :self_serve) }
    let(:sandbox) { create(:organization, :self_serve, :sandbox, production_organization: production) }

    def fetch(current_organization)
      current_membership = user.memberships.active.find_by!(organization: current_organization)
      execute_graphql(current_user: user, current_organization:, current_membership:, query:)["data"]["organization"]
    end

    before { create(:membership, user:, organization: production) }

    it "links each organization to the other one for a member of both" do
      create(:membership, user:, organization: sandbox)

      expect(fetch(production)).to eq(
        "selfServe" => true, "environment" => "production", "productionOrganization" => nil,
        "sandboxOrganization" => {"id" => sandbox.id, "name" => sandbox.name, "slug" => sandbox.slug}
      )
      expect(fetch(sandbox)).to eq(
        "selfServe" => true, "environment" => "sandbox", "sandboxOrganization" => nil,
        "productionOrganization" => {"id" => production.id, "name" => production.name, "slug" => production.slug}
      )
    end

    it "hides the sandbox from a user who is not an active member of it" do
      create(:membership, :revoked, user:, organization: sandbox)

      expect(fetch(production)["sandboxOrganization"]).to be_nil
    end
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
