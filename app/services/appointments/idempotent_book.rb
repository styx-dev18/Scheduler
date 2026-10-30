module Appointments
  class IdempotentBook
    include Dry::Monads[:result]

    MAX_KEY_LENGTH = 255

    def initialize(book: Appointments::Book.new)
      @book = book
    end

    def call(key:, params:)
      return book_and_serialize(params) if key.blank?

      if key.length > MAX_KEY_LENGTH
        return Failure([ "VALIDATION_ERROR", {
          detail: "Invalid Idempotency-Key header",
          errors: { "Idempotency-Key" => [ "is too long (maximum is #{MAX_KEY_LENGTH} characters)" ] },
          extra: nil
        } ])
      end

      fingerprint = fingerprint_for(params)
      existing = IdempotencyKey.find_by(key:)
      return replay(existing, fingerprint) if existing

      claim_and_book(key, fingerprint, params)
    end

    private

    def book_and_serialize(params)
      @book.call(params).fmap { |appointment| serialize(appointment) }
    end

    def claim_and_book(key, fingerprint, params)
      outcome = nil
      ApplicationRecord.transaction do
        claim = claim_key(key, fingerprint)
        if claim
          outcome = @book.call(params)
          raise ActiveRecord::Rollback if outcome.failure?

          appointment = outcome.value!
          body = serialize(appointment)
          claim.update!(appointment_id: appointment.id, response_status: 201, response_body: body)
          outcome = Success(body)
        else
          outcome = replay(IdempotencyKey.find_by!(key:), fingerprint)
        end
      end
      outcome
    end

    def claim_key(key, fingerprint)
      IdempotencyKey.transaction(requires_new: true) do
        IdempotencyKey.create!(key:, request_fingerprint: fingerprint)
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    def replay(row, fingerprint)
      if row.request_fingerprint != fingerprint
        Failure([ "IDEMPOTENCY_KEY_REUSED", { detail: "Idempotency key was used with a different request", errors: nil, extra: nil } ])
      elsif row.response_status.nil?
        Failure([ "IDEMPOTENCY_KEY_IN_PROGRESS", { detail: "A request with this Idempotency-Key is in progress", errors: nil, extra: nil } ])
      else
        Success(row.response_body)
      end
    end

    def serialize(appointment)
      AppointmentSerializer.new(appointment).serializable_hash
    end

    def fingerprint_for(params)
      sorted = params.to_h.transform_keys(&:to_s).sort.to_h
      Digest::SHA256.hexdigest(JSON.generate(sorted))
    end
  end
end
