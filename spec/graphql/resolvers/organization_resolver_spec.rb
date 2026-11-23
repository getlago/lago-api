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

  context "with an organization waiting for a payment method" do
    include_context "with self-serve enabled"

    let(:waiting_organization) { create(:organization, :self_serve, activation_status: "pending_payment_method") }
    let(:waiting_membership) { create(:membership, organization: waiting_organization) }

    it "refuses the query" do
      result = execute_graphql(
        current_user: waiting_membership.user,
        current_organization: waiting_organization,
        current_membership: waiting_membership,
        query:
      )

      expect(result["data"]["organization"]).to be_nil
      expect(result["errors"]).to include hash_including(
        "extensions" => hash_including("status" => 403, "code" => "organization_inactive")
      )
    end
  end

  context "with a production organization and its sandbox" do
    include_context "with self-serve enabled"

    let(:query) do
      <<~GQL
        query {
          organization {
            selfServe environment activationStatus
            productionOrganization { id name slug }
            sandboxOrganization { id name slug }
          }
        }
      GQL
    end

    let(:user) { create(:user) }
    let(:production) { create(:organization, :self_serve, activation_status:) }
    let(:activation_status) { "active" }
    let(:sandbox) { create(:organization, :self_serve, :sandbox, production_organization: production) }
    # The user's membership status in the sandbox, nil for none.
    let(:sandbox_membership_status) { :active }

    def fetch(current_organization)
      current_membership = user.memberships.active.find_by!(organization: current_organization)
      execute_graphql(current_user: user, current_organization:, current_membership:, query:)["data"]["organization"]
    end

    before do
      create(:membership, user:, organization: production)
      create(:membership, user:, organization: sandbox, status: sandbox_membership_status) if sandbox_membership_status
    end

    it "links each organization to the other one for a member of both" do
      expect(fetch(production)).to eq(
        "selfServe" => true, "environment" => "production", "activationStatus" => "active",
        "productionOrganization" => nil,
        "sandboxOrganization" => {"id" => sandbox.id, "name" => sandbox.name, "slug" => sandbox.slug}
      )
      expect(fetch(sandbox)).to eq(
        "selfServe" => true, "environment" => "sandbox", "activationStatus" => "active", "sandboxOrganization" => nil,
        "productionOrganization" => {"id" => production.id, "name" => production.name, "slug" => production.slug}
      )
    end

    context "when the sandbox membership is revoked" do
      let(:sandbox_membership_status) { :revoked }

      it "hides the sandbox from the user" do
        expect(fetch(production)["sandboxOrganization"]).to be_nil
      end
    end

    context "with self-serve disabled and a production waiting for a payment method" do
      let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_ENABLED" => "false") }
      let(:activation_status) { "pending_payment_method" }
      let(:standalone) do
        {"selfServe" => false, "environment" => "production", "activationStatus" => "active",
         "productionOrganization" => nil, "sandboxOrganization" => nil}
      end

      it "opens and shows each organization as an active standalone production one" do
        expect(fetch(production)).to eq(standalone)
        expect(fetch(sandbox)).to eq(standalone)
      end
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
