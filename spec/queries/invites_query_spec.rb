# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvitesQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }

  context "when no filters applied" do
    let!(:invites) do
      [
        create(:invite, organization:),
        create(:invite, organization:, created_at: 2.days.ago),
        create(:invite, organization:, created_at: 1.day.ago)
      ]
    end

    before do
      create(:invite)
      create(:invite, organization:, status: :accepted)
      create(:invite, organization:, status: :revoked)
    end

    it "returns pending invites of the organization ordered by created_at desc" do
      expect(result).to be_success
      expect(result.invites.pluck(:id)).to eq [invites.first.id, invites.third.id, invites.second.id]
    end
  end

  context "when pagination options provided" do
    let(:pagination) { {page: 2, limit: 1} }

    let!(:invites) do
      [
        create(:invite, organization:),
        create(:invite, organization:, created_at: 2.days.ago),
        create(:invite, organization:, created_at: 1.day.ago)
      ]
    end

    it "returns paginated invites" do
      expect(result).to be_success
      expect(result.invites).to contain_exactly invites.third
      expect(result.invites.current_page).to eq 2
      expect(result.invites.total_pages).to eq 3
      expect(result.invites.total_count).to eq 3
    end
  end

  context "when search term filter applied" do
    let!(:matching_invite) { create(:invite, organization:, email: "jane.doe@example.com") }

    before { create(:invite, organization:, email: "john@other.com") }

    context "with term partially matching the email" do
      let(:search_term) { "jane.d" }

      it "returns the matching invites" do
        expect(result).to be_success
        expect(result.invites.pluck(:id)).to contain_exactly matching_invite.id
      end
    end

    context "with term matching the email in a different case" do
      let(:search_term) { "JANE.DOE@EXAMPLE.COM" }

      it "returns the matching invites" do
        expect(result).to be_success
        expect(result.invites.pluck(:id)).to contain_exactly matching_invite.id
      end
    end

    context "with a term containing SQL wildcards" do
      let(:search_term) { "jane%example" }

      it "treats the wildcards as literal characters" do
        expect(result).to be_success
        expect(result.invites).to be_empty
      end
    end

    context "with term matching a non pending invite" do
      let(:search_term) { "revoked" }

      before { create(:invite, organization:, email: "revoked@example.com", status: :revoked) }

      it "returns empty result" do
        expect(result).to be_success
        expect(result.invites).to be_empty
      end
    end

    context "with term not matching any invite" do
      let(:search_term) { "nonexistent" }

      it "returns empty result" do
        expect(result).to be_success
        expect(result.invites).to be_empty
      end
    end
  end

  context "when role_ids filter applied" do
    let(:admin_role) { create(:role, :admin) }
    let(:finance_role) { create(:role, :finance) }
    let(:custom_role) { create(:role, organization:) }

    let!(:admin_invite) { create(:invite, organization:, roles: [admin_role.code]) }
    let!(:custom_invite) { create(:invite, organization:, roles: [custom_role.code]) }

    context "with a single role" do
      let(:filters) { {role_ids: [admin_role.id]} }

      it "returns invites holding that role" do
        expect(result).to be_success
        expect(result.invites.pluck(:id)).to contain_exactly admin_invite.id
      end
    end

    context "with several roles" do
      let(:filters) { {role_ids: [admin_role.id, custom_role.id]} }

      it "returns invites holding any of the roles" do
        expect(result).to be_success
        expect(result.invites.pluck(:id)).to match_array [admin_invite.id, custom_invite.id]
      end
    end

    context "when an invite holds several of the filtered roles" do
      let(:filters) { {role_ids: [admin_role.id, finance_role.id]} }

      let!(:multi_role_invite) { create(:invite, organization:, roles: [admin_role.code, finance_role.code]) }

      it "returns the invite once" do
        expect(result).to be_success
        expect(result.invites.pluck(:id)).to match_array [admin_invite.id, multi_role_invite.id]
      end
    end

    context "with a role of another organization" do
      let(:other_role) { create(:role, organization: create(:organization)) }
      let(:filters) { {role_ids: [other_role.id]} }

      before { create(:invite, organization:, roles: [other_role.code]) }

      it "returns no invite" do
        expect(result).to be_success
        expect(result.invites).to be_empty
      end
    end

    context "with an unknown role id" do
      let(:filters) { {role_ids: [SecureRandom.uuid]} }

      it "returns no invite" do
        expect(result).to be_success
        expect(result.invites).to be_empty
      end
    end
  end

  context "when search term and role_ids filters are combined" do
    let(:admin_role) { create(:role, :admin) }
    let(:search_term) { "jane" }
    let(:filters) { {role_ids: [admin_role.id]} }

    let!(:matching_invite) { create(:invite, organization:, email: "jane.doe@example.com", roles: [admin_role.code]) }

    before do
      create(:invite, organization:, email: "john@example.com", roles: [admin_role.code])
      create(:invite, organization:, email: "jane.roe@example.com", roles: [create(:role, organization:).code])
    end

    it "returns invites matching both filters" do
      expect(result).to be_success
      expect(result.invites.pluck(:id)).to contain_exactly matching_invite.id
    end
  end
end
