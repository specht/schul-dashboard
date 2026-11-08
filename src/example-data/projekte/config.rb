PROJEKTTAGE_CATEGORIES = ['drinnen', 'draußen', 'kreativ', 'sportlich', 'musisch']

PROJEKTWAHL_VOTE_END = '2024-06-14T23:59:00'
PROJEKTWAHL_SWAP_PHASE_END = '2024-06-21T23:59:00'

# main.rb ruft beide Funktionen beim Aufbau des Menüs für jede Schülerseite
# auf; in einer Installation müssen sie hier definiert sein. Für die
# Beispieldaten: Projekttage sind nicht aktiv, niemand organisiert ein Projekt.
def email_is_projekttage_organizer?(user_info, email)
    false
end

def projekttage_phase
    0
end
