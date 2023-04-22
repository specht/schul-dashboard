ZEUGNIS_SCHULJAHR = '2022_23'
ZEUGNIS_HALBJAHR = '1'
ZEUGNIS_DATUM = '27.01.2023'

ZEUGNIS_KLASSEN_ORDER = KLASSEN_ORDER.reject { |x| ['11', '12', 'WK1', 'WK2'].include?(x) }

FAECHER_FOR_ZEUGNIS = {
    '2022_23' => {
        '1' => {
            '5' => %w(D En La Gewi Ma Nawi Ku Mu Sp),
            '6' => %w(D En La Gewi Ma Nawi Ku Mu Sp),
            '7' => %w(D En La Eth Ek Ge Pb Ma Bio Ph Ku Mu Sp ITG),
            '7_sesb' => %w(D Ngr En Eth Ek Ge Pol Ma Bio Ch Ph Ku Mu Sp $Fr),
            '8' => %w(D En La Agr Eth Ek Ge Pb Ma Ch Ph Ku Mu Sp),
            '8_sesb' => %w(D Ngr En Eth Ek Ge Pol Ma Bio Ch Ph Ku Mu Sp ITG $Fr $Agr),
            '9' => %w(D En La Agr Eth Ek Ge Pb Ma Bio Ch Ph Ku Mu Sp In $Fr),
            '9_sesb' => %w(D Ngr En Eth Ek Ge Pol Ma Bio Ch Ph Ku Mu Sp In $Fr $Agr),
            '10' => %w(D En La Agr Eth Ek Ge Pb Ma Bio Ch Ph Ku Mu Sp $In $Fr),
            '10_sesb' => %w(D Ngr En Eth Ek Ge Pol Ma Bio Ch Ph Ku Mu Sp Fr $In $Agr),
        },
    },
}

ANLAGE_AS_FOR_ZEUGNIS = {
    '2022_23' => {
        '1' => %w(5 6 7 7_sesb 8 8_sesb 9_sesb)
    },
}

ZEUGNIS_CONSOLIDATE_FACH = {
    'DeP' => 'D',
    'NgrP' => 'Ngr',
    'GeNgr' => 'Ge',
    'PolNgr' => 'Pol',
    'BioNgr' => 'Bio',
    'EkNgr' => 'Ek',
    'EthNgr' => 'Eth',
    'SpoM' => 'Sp',
    'SpoJ' => 'Sp',
}
