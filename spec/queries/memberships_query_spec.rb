# frozen_string_literal: true

require "rails_helper"

RSpec.describe MembershipsQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }

  context "when no filters applied" do
    let!(:memberships) do
      [
        create(:membership, organization:),
        create(:membership, organization:, created_at: 2.days.ago),
        create(:membership, organization:, created_at: 1.day.ago)
      ]
    end

    before do
      create(:membership)
      create(:membership, :revoked, organization:)
    end

    it "returns active memberships of the organization ordered by created_at desc" do
      expect(result).to be_success
      expect(result.memberships.pluck(:id)).to eq [memberships.first.id, memberships.third.id, memberships.second.id]
    end
  end

  context "when pagination options provided" do
    let(:pagination) { {page: 2, limit: 1} }

    let!(:memberships) do
      [
        create(:membership, organization:),
        create(:membership, organization:, created_at: 2.days.ago),
        create(:membership, organization:, created_at: 1.day.ago)
      ]
    end

    it "returns paginated memberships" do
      expect(result).to be_success
      expect(result.memberships).to contain_exactly memberships.third
      expect(result.memberships.current_page).to eq 2
      expect(result.memberships.total_pages).to eq 3
      expect(result.memberships.total_count).to eq 3
    end
  end

  context "when search term filter applied" do
    let!(:matching_membership) do
      create(:membership, organization:, user: create(:user, email: "jane.doe@example.com"))
    end

    before { create(:membership, organization:, user: create(:user, email: "john@other.com")) }

    context "with term partially matching the user email" do
      let(:search_term) { "jane.d" }

      it "returns the matching memberships" do
        expect(result).to be_success
        expect(result.memberships.pluck(:id)).to contain_exactly matching_membership.id
      end
    end

    context "with term matching the user email in a different case" do
      let(:search_term) { "JANE.DOE@EXAMPLE.COM" }

      it "returns the matching memberships" do
        expect(result).to be_success
        expect(result.memberships.pluck(:id)).to contain_exactly matching_membership.id
      end
    end

    context "with a term containing SQL wildcards" do
      let(:search_term) { "jane%example" }

      it "treats the wildcards as literal characters" do
        expect(result).to be_success
        expect(result.memberships).to be_empty
      end
    end

    context "with term not matching any membership" do
      let(:search_term) { "nonexistent" }

      it "returns empty result" do
        expect(result).to be_success
        expect(result.memberships).to be_empty
      end
    end

    context "when the matching user belongs to another organization" do
      let(:search_term) { "jane.doe@example.com" }

      before { create(:membership, user: matching_membership.user) }

      it "returns the membership of the current organization only" do
        expect(result).to be_success
        expect(result.memberships.pluck(:id)).to contain_exactly matching_membership.id
      end
    end
  end

  context "when role_ids filter applied" do
    let(:admin_role) { create(:role, :admin) }
    let(:finance_role) { create(:role, :finance) }
    let(:custom_role) { create(:role, organization:) }

    let!(:admin_membership) { create(:membership, organization:, role: admin_role) }
    let!(:finance_membership) { create(:membership, organization:, role: finance_role) }
    let!(:custom_membership) { create(:membership, organization:, role: custom_role) }

    context "with a single role" do
      let(:filters) { {role_ids: [admin_role.id]} }

      it "returns memberships holding that role" do
        expect(result).to be_success
        expect(result.memberships.pluck(:id)).to contain_exactly admin_membership.id
      end
    end

    context "with several roles" do
      let(:filters) { {role_ids: [admin_role.id, custom_role.id]} }

      it "returns memberships holding any of the roles" do
        expect(result).to be_success
        expect(result.memberships.pluck(:id)).to match_array [admin_membership.id, custom_membership.id]
      end
    end

    context "when a membership holds several of the filtered roles" do
      let(:filters) { {role_ids: [admin_role.id, finance_role.id]} }

      before { create(:membership_role, membership: admin_membership, role: finance_role) }

      it "returns the membership once" do
        expect(result).to be_success
        expect(result.memberships.pluck(:id)).to match_array [admin_membership.id, finance_membership.id]
      end
    end

    context "when the role has been discarded" do
      let(:filters) { {role_ids: [custom_role.id]} }

      before { custom_role.discard! }

      it "returns no membership" do
        expect(result).to be_success
        expect(result.memberships).to be_empty
      end
    end

    context "with a role of another organization" do
      let(:other_role) { create(:role, organization: create(:organization)) }
      let(:filters) { {role_ids: [other_role.id]} }

      before { create(:membership, organization: other_role.organization, role: other_role) }

      it "returns no membership" do
        expect(result).to be_success
        expect(result.memberships).to be_empty
      end
    end
  end

  context "when search term and role_ids filters are combined" do
    let(:admin_role) { create(:role, :admin) }
    let(:search_term) { "jane" }
    let(:filters) { {role_ids: [admin_role.id]} }

    let!(:matching_membership) do
      create(:membership, organization:, role: admin_role, user: create(:user, email: "jane.doe@example.com"))
    end

    before do
      create(:membership, organization:, role: admin_role, user: create(:user, email: "john@example.com"))
      create(:membership, organization:, user: create(:user, email: "jane.roe@example.com"))
    end

    it "returns memberships matching both filters" do
      expect(result).to be_success
      expect(result.memberships.pluck(:id)).to contain_exactly matching_membership.id
    end
  end
end
