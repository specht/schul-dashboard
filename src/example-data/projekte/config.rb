PROJEKTWAHL_VOTE_END = '2026-04-01 12:00'
PROJEKTTAGE_PHASE = 0

class Main < Sinatra::Base
    def projekttage_phase
        PROJEKTTAGE_PHASE
    end
end

class Main < Sinatra::Base
    def email_is_projekttage_organizer?(email, x = nil)
        false
    end
end
