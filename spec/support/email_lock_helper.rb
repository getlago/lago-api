# frozen_string_literal: true

module EmailLockHelper
  # Holds Users::EmailLockService for an address in another thread while the block runs. Needs `transaction: false`.
  def with_email_lock(email)
    locked = Queue.new
    release = Queue.new
    thread = Thread.new do
      Users::EmailLockService.call(email:) do
        locked.push(true)
        release.pop
      end
    end
    locked.pop
    yield
  ensure
    release&.push(true)
    thread&.join
  end
end
