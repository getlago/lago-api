# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::MigrationsIfNotExistsCop, :config do
  describe "schema additions" do
    it "registers an offense for an unguarded column" do
      expect_offense(<<~RUBY)
        add_column :fees, :contract_id, :uuid
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use if_not_exists: true when adding schema objects in a migration so retries can resume.
      RUBY
    end

    it "registers an offense for an unguarded index" do
      expect_offense(<<~RUBY)
        add_index :fees, :contract_id, algorithm: :concurrently
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use if_not_exists: true when adding schema objects in a migration so retries can resume.
      RUBY
    end

    it "registers an offense for an unguarded foreign key" do
      expect_offense(<<~RUBY)
        add_foreign_key :fees, :contracts, validate: false
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use if_not_exists: true when adding schema objects in a migration so retries can resume.
      RUBY
    end

    it "registers an offense for an unguarded check constraint" do
      expect_offense(<<~RUBY)
        add_check_constraint :fees, "contract_id IS NOT NULL"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use if_not_exists: true when adding schema objects in a migration so retries can resume.
      RUBY
    end

    it "registers an offense when the guard is false" do
      expect_offense(<<~RUBY)
        add_index :fees, :contract_id, if_not_exists: false
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use if_not_exists: true when adding schema objects in a migration so retries can resume.
      RUBY
    end

    it "registers an offense when the guard is not statically true" do
      expect_offense(<<~RUBY)
        add_column :fees, :contract_id, :uuid, if_not_exists: retryable
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use if_not_exists: true when adding schema objects in a migration so retries can resume.
      RUBY
    end

    it "allows guarded schema additions" do
      expect_no_offenses(<<~RUBY)
        add_column :fees, :contract_id, :uuid, if_not_exists: true
        add_index(:fees, :contract_id, algorithm: :concurrently, if_not_exists: true)
        add_foreign_key :fees, :contracts, validate: false, if_not_exists: true
        add_check_constraint :fees, "contract_id IS NOT NULL", if_not_exists: true
      RUBY
    end

    it "ignores unrelated calls" do
      expect_no_offenses(<<~RUBY)
        remove_index :fees, :contract_id
        helper.add_column :fees, :contract_id, :uuid
      RUBY
    end
  end
end
