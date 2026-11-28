# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::PerformLaterInTransactionCop, :config do
  let(:message) { "Do not call `%s` inside a transaction: the job can run before the commit. Use `perform_after_commit` or an `after_commit {}` block." }

  it "registers an offense and corrects perform_later inside ActiveRecord::Base.transaction" do
    expect_offense(<<~RUBY, message: format(message, "perform_later"))
      ActiveRecord::Base.transaction do
        plan.update!(pending_deletion: true)
        Plans::DestroyJob.perform_later(plan)
                          ^^^^^^^^^^^^^ %{message}
      end
    RUBY

    expect_correction(<<~RUBY)
      ActiveRecord::Base.transaction do
        plan.update!(pending_deletion: true)
        Plans::DestroyJob.perform_after_commit(plan)
      end
    RUBY
  end

  it "registers an offense inside a model transaction and a nested block" do
    expect_offense(<<~RUBY, message: format(message, "perform_later"))
      Invoice.transaction do
        invoices.each do |invoice|
          Invoices::FinalizeJob.perform_later(invoice) if invoice.draft?
                                ^^^^^^^^^^^^^ %{message}
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      Invoice.transaction do
        invoices.each do |invoice|
          Invoices::FinalizeJob.perform_after_commit(invoice) if invoice.draft?
        end
      end
    RUBY
  end

  it "registers an offense inside with_lock" do
    expect_offense(<<~RUBY, message: format(message, "perform_later"))
      wallet.with_lock do
        Wallets::RefreshJob.perform_later(wallet)
                            ^^^^^^^^^^^^^ %{message}
      end
    RUBY
  end

  it "registers an offense without correction for a configured job" do
    expect_offense(<<~RUBY, message: format(message, "perform_later"))
      ActiveRecord::Base.transaction do
        Invoices::UpdateJob.set(wait: 30.seconds).perform_later(invoice)
                                                  ^^^^^^^^^^^^^ %{message}
      end
    RUBY

    expect_no_corrections
  end

  it "registers an offense without correction when the job is read" do
    expect_offense(<<~RUBY, message: format(message, "perform_later"))
      ActiveRecord::Base.transaction do
        job = Invoices::UpdateJob.perform_later(invoice)
                                  ^^^^^^^^^^^^^ %{message}
      end
    RUBY

    expect_no_corrections
  end

  it "registers an offense for perform_all_later and deliver_later" do
    expect_offense(<<~RUBY, message_all: format(message, "perform_all_later"), message_mail: format(message, "deliver_later"))
      ActiveRecord::Base.transaction do
        ApplicationJob.perform_all_later(jobs)
                       ^^^^^^^^^^^^^^^^^ %{message_all}
        InvoiceMailer.with(invoice: invoice).created.deliver_later
                                                     ^^^^^^^^^^^^^ %{message_mail}
      end
    RUBY

    expect_no_corrections
  end

  it "does not register an offense inside an after_commit block" do
    expect_no_offenses(<<~RUBY)
      ActiveRecord::Base.transaction do
        after_commit { Plans::DestroyJob.perform_later(plan) }
      end
    RUBY
  end

  it "does not register an offense for perform_after_commit" do
    expect_no_offenses(<<~RUBY)
      ActiveRecord::Base.transaction do
        Plans::DestroyJob.perform_after_commit(plan)
      end
    RUBY
  end

  it "does not register an offense outside a transaction" do
    expect_no_offenses(<<~RUBY)
      ActiveRecord::Base.transaction { plan.update!(pending_deletion: true) }
      Plans::DestroyJob.perform_later(plan)
    RUBY
  end

  it "does not register an offense in a method defined inside a transaction block" do
    expect_no_offenses(<<~RUBY)
      ActiveRecord::Base.transaction do
        def enqueue
          Plans::DestroyJob.perform_later(plan)
        end
      end
    RUBY
  end
end
