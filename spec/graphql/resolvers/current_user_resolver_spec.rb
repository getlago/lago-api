# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CurrentUserResolver do
  let(:admin_role) { create(:role, :admin) }

  let(:query) do
    <<~GRAPHQL
      query {
        currentUser {
          id
          email
          premium
          memberships {
            roles
            status
            organization {
              name
            }
          }
        }
      }
    GRAPHQL
  end

  it "returns current_user" do
    user = create(:user)
    membership = create(:membership, user:)
    create(:membership_role, membership:, role: admin_role)

    result = execute_graphql(
      current_user: user,
      query:
    )

    expect(result["data"]["currentUser"]["email"]).to eq(user.email)
    expect(result["data"]["currentUser"]["id"]).to eq(user.id)
    expect(result["data"]["currentUser"]["premium"]).to be_falsey
    expect(result["data"]["currentUser"]["memberships"][0]["roles"]).to eq ["Admin"]
    expect(result["data"]["currentUser"]["memberships"][0]["organization"]["name"]).not_to be_empty
  end

  it "returns null for deprecated role field when using custom role" do
    membership = create(:membership)
    custom_role = create(:role, name: "Developer", organization: membership.organization, permissions: %w[organization:view])
    create(:membership_role, membership:, role: custom_role)

    result = execute_graphql(current_user: membership.user, query:)

    expect(result["data"]["currentUser"]["memberships"][0]["role"]).to be_nil
    expect(result["data"]["currentUser"]["memberships"][0]["roles"]).to eq(["Developer"])
  end

  describe "with organizations instead of memberships" do
    let(:query) do
      <<~GRAPHQL
        query {
          currentUser {
            id
            email
            premium
            organizations {
              id
            }
          }
        }
      GRAPHQL
    end

    it "returns organizations" do
      organization = create(:organization)
      membership = create(:membership, organization:)
      result = execute_graphql(
        current_user: membership.user,
        query:
      )

      expect(result["data"]["currentUser"]["organizations"][0]["id"]).to eq organization.id
    end
  end

  describe "with revoked membership" do
    let(:membership) { create(:membership) }
    let(:revoked_membership) do
      create(:membership, user: membership.user, status: :revoked)
    end

    before do
      create(:membership_role, membership:, role: admin_role)
      revoked_membership
    end

    it "only lists organizations when membership has an active status" do
      result = execute_graphql(
        current_user: membership.user,
        query:
      )

      expect(result["data"]["currentUser"]["memberships"]).not_to include(revoked_membership)
    end
  end

  describe "with a production organization and its sandbox" do
    include_context "with self-serve enabled"

    let(:query) do
      <<~GRAPHQL
        query {
          currentUser {
            memberships {
              organization {
                id selfServe environment
                productionOrganization { id name slug }
                sandboxOrganization { id name slug }
              }
            }
            organizations { id }
          }
        }
      GRAPHQL
    end

    let(:user) { create(:user) }
    let(:production) { create(:organization, :self_serve) }
    let(:sandbox) { create(:organization, :self_serve, :sandbox, production_organization: production) }
    let(:other) { create(:organization) }
    # Membership creation dates, oldest first, and the memberships created revoked.
    let(:membership_dates) { {other: 3.days.ago, sandbox: 2.days.ago, production: 1.day.ago} }
    let(:revoked) { [] }

    before do
      membership_dates.each do |key, created_at|
        status = revoked.include?(key) ? :revoked : :active
        create(:membership, user:, organization: public_send(key), created_at:, status:)
      end
    end

    def organizations_of(result)
      result["data"]["currentUser"]["memberships"].map { it["organization"] }
    end

    def linked(organization)
      {"id" => organization.id, "name" => organization.name, "slug" => organization.slug}
    end

    it "shows the pair, each sandbox right after its production organization, oldest membership first" do
      result = execute_graphql(current_user: user, query:)

      expect(organizations_of(result)).to eq([
        {"id" => other.id, "selfServe" => false, "environment" => "production", "productionOrganization" => nil,
         "sandboxOrganization" => nil},
        {"id" => production.id, "selfServe" => true, "environment" => "production", "productionOrganization" => nil,
         "sandboxOrganization" => linked(sandbox)},
        {"id" => sandbox.id, "selfServe" => true, "environment" => "sandbox",
         "productionOrganization" => linked(production), "sandboxOrganization" => nil}
      ])
      expect(result["data"]["currentUser"]["organizations"].pluck("id")).to eq([other.id, production.id, sandbox.id])
    end

    context "when another membership falls between the pair" do
      let(:membership_dates) { {production: 3.days.ago, other: 2.days.ago, sandbox: 1.day.ago} }

      it "keeps the pair together" do
        result = execute_graphql(current_user: user, query:)

        expect(organizations_of(result).pluck("id")).to eq([production.id, sandbox.id, other.id])
      end
    end

    context "when the sandbox membership is revoked" do
      let(:membership_dates) { {production: 2.days.ago, sandbox: 1.day.ago} }
      let(:revoked) { [:sandbox] }

      it "hides the sandbox and the link to it" do
        result = execute_graphql(current_user: user, query:)

        expect(organizations_of(result).pluck("id", "sandboxOrganization")).to eq([[production.id, nil]])
      end
    end

    context "when the production membership is revoked" do
      let(:revoked) { [:production] }

      it "keeps the sandbox in its own place, without the link to production" do
        result = execute_graphql(current_user: user, query:)

        expect(organizations_of(result).pluck("id", "productionOrganization")).to eq([[other.id, nil], [sandbox.id, nil]])
      end
    end

    context "when the user has no production membership" do
      let(:membership_dates) { {sandbox: 2.days.ago, other: 1.day.ago} }

      it "keeps the sandbox in its own place" do
        result = execute_graphql(current_user: user, query:)

        expect(organizations_of(result).pluck("id")).to eq([sandbox.id, other.id])
      end
    end

    context "with more pairs" do
      let(:membership_dates) { {production: 2.days.ago, sandbox: 1.day.ago} }

      def pair_queries
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { execute_graphql(current_user: user, query:) }
        count
      end

      it "loads the links with the same number of queries whatever the number of pairs" do
        one_pair = pair_queries

        2.times do
          pair_production = create(:organization, :self_serve)
          create(:membership, user:, organization: pair_production)
          create(:membership, user:, organization: create(:organization, :sandbox, production_organization: pair_production))
        end

        expect(pair_queries).to eq(one_pair)
      end
    end

    context "with self-serve disabled" do
      let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_ENABLED" => "false") }
      let(:membership_dates) { {production: 3.days.ago, other: 2.days.ago, sandbox: 1.day.ago} }

      it "shows each organization of the pair as a standalone production one, in membership order" do
        result = execute_graphql(current_user: user, query:)

        expect(organizations_of(result)).to eq([
          {"id" => production.id, "selfServe" => false, "environment" => "production",
           "productionOrganization" => nil, "sandboxOrganization" => nil},
          {"id" => other.id, "selfServe" => false, "environment" => "production",
           "productionOrganization" => nil, "sandboxOrganization" => nil},
          {"id" => sandbox.id, "selfServe" => false, "environment" => "production",
           "productionOrganization" => nil, "sandboxOrganization" => nil}
        ])
      end
    end
  end

  context "with no current_user" do
    it "returns an error" do
      result = execute_graphql(query:)

      expect_unauthorized_error(result)
    end
  end

  describe "needsOrganization" do
    let(:query) { "query { currentUser { needsOrganization memberships { id } organizations { id } } }" }

    def current_user_data(user)
      execute_graphql(current_user: user, query:)["data"]["currentUser"]
    end

    context "when self-serve is on" do
      include_context "with self-serve enabled"

      it "is true for a self-serve user who never had an organization, with empty lists" do
        expect(current_user_data(create(:user, :self_serve)))
          .to eq("needsOrganization" => true, "memberships" => [], "organizations" => [])
      end

      it "is false for a legacy user without membership and for a revoked self-serve user" do
        revoked = create(:user, :self_serve)
        create(:membership, :revoked, user: revoked)

        expect(current_user_data(create(:user))["needsOrganization"]).to be(false)
        expect(current_user_data(revoked)["needsOrganization"]).to be(false)
      end
    end

    it "is false when self-serve is off" do
      expect(current_user_data(create(:user, :self_serve))["needsOrganization"]).to be(false)
    end
  end
end
