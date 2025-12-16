# frozen_string_literal: true

require "rails_helper"

RSpec.describe MembershipRole do
  subject(:membership_role) { build(:membership_role) }

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:membership)
      expect(subject).to belong_to(:role)
    end
  end

  describe ".admins" do
    it "returns only admin member roles" do
      membership_role = create(:membership_role)
      admin_role_id = SecureRandom.uuid

      described_class.connection.execute(<<~SQL)
        INSERT INTO roles (id, name, admin, permissions, created_at, updated_at)
        VALUES ('#{admin_role_id}', 'TestAdmin', true, ARRAY[]::text[], now(), now())
      SQL

      admin_membership_role_id = SecureRandom.uuid
      described_class.connection.execute(<<~SQL)
        INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
        VALUES (
          '#{admin_membership_role_id}',
          '#{membership_role.organization_id}',
          '#{membership_role.membership_id}',
          '#{admin_role_id}',
          now(),
          now()
        )
      SQL

      expect(described_class.admins.pluck(:id)).to eq([admin_membership_role_id])
    end
  end

  describe "validations" do
    it "forbids discarding the last admin role in organization" do
      membership = create(:membership)
      admin_role_id = SecureRandom.uuid

      described_class.connection.execute(<<~SQL)
        INSERT INTO roles (id, name, admin, permissions, created_at, updated_at)
        VALUES ('#{admin_role_id}', 'TestAdmin', true, ARRAY[]::text[], now(), now())
      SQL

      membership_role_id = SecureRandom.uuid
      described_class.connection.execute(<<~SQL)
        INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
        VALUES (
          '#{membership_role_id}',
          '#{membership.organization_id}',
          '#{membership.id}',
          '#{admin_role_id}',
          now(),
          now()
        )
      SQL

      membership_role = described_class.find(membership_role_id)

      expect(membership_role.discard).to be(false)
    end

    it "allows discarding admin role when another admin exists" do
      membership = create(:membership)
      other_membership = create(:membership, organization: membership.organization)
      admin_role_id = SecureRandom.uuid
      custom_role = create(:role, organization: membership.organization)

      described_class.connection.execute(<<~SQL)
        INSERT INTO roles (id, name, admin, permissions, created_at, updated_at)
        VALUES ('#{admin_role_id}', 'TestAdmin', true, ARRAY[]::text[], now(), now())
      SQL

      membership_role_id = SecureRandom.uuid
      described_class.connection.execute(<<~SQL)
        INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
        VALUES (
          '#{membership_role_id}',
          '#{membership.organization_id}',
          '#{membership.id}',
          '#{admin_role_id}',
          now(),
          now()
        )
      SQL

      # Add second role to membership so it's not the last
      create(:membership_role, membership:, organization: membership.organization, role: custom_role)

      described_class.connection.execute(<<~SQL)
        INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
        VALUES (
          '#{SecureRandom.uuid}',
          '#{other_membership.organization_id}',
          '#{other_membership.id}',
          '#{admin_role_id}',
          now(),
          now()
        )
      SQL

      membership_role = described_class.find(membership_role_id)

      expect(membership_role.discard).to be(true)
    end

    it "forbids discarding the last role of membership" do
      membership_role = create(:membership_role)

      expect(membership_role.discard).to be(false)
    end

    it "allows discarding role when membership has another role" do
      membership_role = create(:membership_role)
      other_role = create(:role, organization: membership_role.organization)
      create(:membership_role, membership: membership_role.membership, organization: membership_role.organization, role: other_role)

      expect(membership_role.discard).to be(true)
    end
  end

  describe "database constraints" do
    it "rejects duplicate role for same membership" do
      membership_role = create(:membership_role)

      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
          VALUES (
            '#{SecureRandom.uuid}',
            '#{membership_role.organization_id}',
            '#{membership_role.membership_id}',
            '#{membership_role.role_id}',
            now(),
            now()
          )
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "allows same role for different memberships" do
      membership_role = create(:membership_role)
      other_membership = create(:membership, organization: membership_role.organization)

      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
          VALUES (
            '#{SecureRandom.uuid}',
            '#{membership_role.organization_id}',
            '#{other_membership.id}',
            '#{membership_role.role_id}',
            now(),
            now()
          )
        SQL
      }.not_to raise_error
    end

    it "rejects organization mismatch with membership" do
      membership = create(:membership)
      role = create(:role, organization: membership.organization)
      other_organization = create(:organization)

      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
          VALUES (
            '#{SecureRandom.uuid}',
            '#{other_organization.id}',
            '#{membership.id}',
            '#{role.id}',
            now(),
            now()
          )
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects role from different organization" do
      membership = create(:membership)
      other_organization = create(:organization)
      role = create(:role, organization: other_organization)

      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO membership_roles (id, organization_id, membership_id, role_id, admin, created_at, updated_at)
          VALUES (
            '#{SecureRandom.uuid}',
            '#{membership.organization_id}',
            '#{membership.id}',
            '#{role.id}',
            false,
            now(),
            now()
          )
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "allows predefined role (without organization)" do
      membership = create(:membership)
      admin_role_id = SecureRandom.uuid

      described_class.connection.execute(<<~SQL)
        INSERT INTO roles (id, name, admin, permissions, created_at, updated_at)
        VALUES ('#{admin_role_id}', 'TestAdmin', true, ARRAY[]::text[], now(), now())
      SQL

      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO membership_roles (id, organization_id, membership_id, role_id, created_at, updated_at)
          VALUES (
            '#{SecureRandom.uuid}',
            '#{membership.organization_id}',
            '#{membership.id}',
            '#{admin_role_id}',
            now(),
            now()
          )
        SQL
      }.not_to raise_error
    end

    it "prevents hard deletion" do
      membership_role = create(:membership_role)

      expect {
        described_class.connection.execute("DELETE FROM membership_roles WHERE id = '#{membership_role.id}'")
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "prevents modification of revoked member role" do
      membership_role = create(:membership_role)
      other_role = create(:role, organization: membership_role.organization)
      create(:membership_role, membership: membership_role.membership, organization: membership_role.organization, role: other_role)
      membership_role.discard!

      expect {
        described_class.connection.execute(<<~SQL)
          UPDATE membership_roles SET updated_at = now() WHERE id = '#{membership_role.id}'
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "prevents moving to different organization" do
      membership_role = create(:membership_role)
      other_organization = create(:organization)

      expect {
        described_class.connection.execute(<<~SQL)
          UPDATE membership_roles SET organization_id = '#{other_organization.id}' WHERE id = '#{membership_role.id}'
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "prevents moving to different role" do
      membership_role = create(:membership_role)
      other_role = create(:role, organization: membership_role.organization)

      expect {
        described_class.connection.execute(<<~SQL)
          UPDATE membership_roles SET role_id = '#{other_role.id}' WHERE id = '#{membership_role.id}'
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
