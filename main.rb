require "json"
require "csv"
require "write_xlsx"

CONFIG = JSON.load_file! "config/artifacts_config.json"
LOC_ATTRS = JSON.load_file! "locales/#{CONFIG["locale"]}.attributes.json"
LOC_CHARS = JSON.load_file! "locales/#{CONFIG["locale"]}.characters.json"
LOC_LOG = JSON.load_file! "locales/#{CONFIG["locale"]}.artifacts_log.json"

ARTIFACTS_ATTRS = {
    "flower" => {},
    "plume" => {},
    "sands" => {},
    "goblet" => {},
    "circlet" => {},
}
KEY_MAIN_ATTR = {
    LOC_ATTRS["atk"] => "atk_",
    LOC_ATTRS["def"] => "def_",
    LOC_ATTRS["hp"] => "hp_",
    LOC_ATTRS["eleMas"] => "eleMas",
}
LOC_ATTRS.each { |k,v| KEY_MAIN_ATTR[v] = k if k.match("_dmg_") }
LOC_ARTIFACTS = JSON.load_file! "locales/#{CONFIG["locale"]}.artifacts_sets.json"
CHAR_CONFIG = CSV.read "config/#{CONFIG["locale"]}.artifacts_equip.csv", headers: true
DISABLED_CHARS = if File.exists? "yas/disabled_chars.txt"
        File.read("yas/disabled_chars.txt").split
    else [] end
chars_requirements = {}

# 根据人物主堆属性确定各主属性下属词条
CHAR_CONFIG.each do |c|
    next if c["enable"].upcase != "TRUE" || DISABLED_CHARS.include?(c["char"])

    c_attr = {
        "char" => c["char"],
        "sub_attr" => [],
        "multi" => false,
        "sets" => LOC_ARTIFACTS.filter{|k,v| c[v]}.keys,
    }
    main_attr = {
        "flower" => ["hp"],
        "plume" => ["atk"],
        "sands" => [],
        "goblet" => [],
        "circlet" => [],
    }

    ["mainAttr", "mainAttr2", "subAttr"].each do |x|
        case c[x]
        when LOC_ATTRS["atk"] then c_attr["sub_attr"] += ["atk_", "atk"]
        when LOC_ATTRS["def"] then c_attr["sub_attr"] += ["def_", "def"]
        when LOC_ATTRS["hp"] then c_attr["sub_attr"] += ["hp_", "hp"]
        when LOC_ATTRS["eleMas"] then c_attr["sub_attr"] += ["eleMas"]
        end
    end
    c_attr["multi"] = true if (c_attr["sub_attr"] & %w(atk def hp)).length > 1

    main_attr["sands"] += ["enerRech_"] if c["ER"].to_i > 1
    c_attr["sub_attr"] += ["enerRech_"] if c["ER"].to_i > 0

    main_attr["goblet"] << KEY_MAIN_ATTR[c["elem"]] if KEY_MAIN_ATTR[c["elem"]]

    case c["CR"].to_i
    when -1 then main_attr["circlet"] += ["heal_"]
    when 1
        c_attr["sub_attr"] += ["critRate_"]
        main_attr["circlet"] += ["critRate_"]
    when 2
        c_attr["sub_attr"] += ["critDMG_"]
        main_attr["circlet"] += ["critDMG_"]
    when 3
        c_attr["sub_attr"] += ["critRate_", "critDMG_"]
        main_attr["circlet"] += ["critRate_", "critDMG_"]
    end

    ["sands", "goblet", "circlet"].each do |x|
        next if !CONFIG["allow_substitution"] && main_attr[x]
        main_attr[x] << KEY_MAIN_ATTR[c["mainAttr"]]
        main_attr[x] << KEY_MAIN_ATTR[c["mainAttr2"]] if KEY_MAIN_ATTR[c["mainAttr2"]]
        main_attr[x].uniq!
    end
    c_attr["sub_attr"].uniq!

    chars_requirements[c_attr["char"]] = {
        "sets" => c_attr["sets"].map{|x| LOC_ARTIFACTS[x]},
        "sub_attr" => c_attr["sub_attr"].map{|x| LOC_ATTRS[x]}.uniq
    }
    main_attr.each do |s,t|
        t.uniq.each do |a|
            th = (c_attr["sub_attr"] - [a]).sum(0) do |x|
                %w(atk def hp).include?(x) ? 0.5 : 1
            end
            ARTIFACTS_ATTRS[s][a] ||= []
            ARTIFACTS_ATTRS[s][a] << c_attr.merge({"threshold" => th})
        end
    end
end

SUB_STAT_BASE_VALUES = {
    "hp"=>[10.0, 29.9, 71.7, 143.4, 239.0, 298.8],
    "atk"=>[1.0, 2.0, 4.7, 9.3, 15.6, 19.5],
    "def"=>[1.0, 2.3, 5.6, 11.1, 18.5, 23.2],
    "hp_"=>[1.0, 1.5, 2.3, 3.5, 4.7, 5.8],
    "atk_"=>[1.0, 1.5, 2.3, 3.5, 4.7, 5.8],
    "def_"=>[1.0, 1.8, 2.9, 4.4, 5.8, 7.3],
    "eleMas"=>[1.0, 5.8, 9.3, 14.0, 18.6, 23.3],
    "enerRech_"=>[1.0, 1.6, 2.6, 3.9, 5.2, 6.5],
    "critRate_"=>[1.0, 1.0, 1.6, 2.3, 3.1, 3.9],
    "critDMG_"=>[1.0, 1.9, 3.1, 4.7, 6.2, 7.8],
}
# 计算价值并根据设置决定圣遗物去留
FORCE_UNLOCK = ARGV.include? "-f"
lock_artifacts = []
result_file = WriteXLSX.new "yas/artifacts.detail.#{Time.now.to_i}.xlsx"
result_table = result_file.add_worksheet
format_corset = { bg_color: "yellow" }
format_useful = { color: "red" }

CSV_PREFIX = %w[No. set slot mainAttr subAttr ownedBy locked lock-pending]
result_table.write_row 0, 0, CSV_PREFIX + chars_requirements.keys
result_table.write 1, 1, LOC_LOG["detail_note"]
result_table.write_row 1, CSV_PREFIX.length, chars_requirements.values.map{|x| x["sub_attr"].join(",")}

ALL_ARTIFACTS = JSON.load_file!("yas/good.json")["artifacts"]
ALL_ARTIFACTS.each_with_index do |a,i|
    info = [
        i,
        LOC_ARTIFACTS[a["setKey"]],
        LOC_LOG[a["slotKey"]],
        LOC_ATTRS[a["mainStatKey"]],
        a["substats"].map{|x| LOC_ATTRS[x["key"]]}.join(","),
        LOC_CHARS[a["location"]],
        a["lock"],
        nil,
    ]
    info[-1] = LOC_LOG["set_not_used"] if !ARTIFACTS_ATTRS[a["slotKey"]]
    info[-1] = LOC_LOG["main_attr_not_used"] if !ARTIFACTS_ATTRS[a["slotKey"]][a["mainStatKey"]]
    next result_table.write_row i + 2, 0, info if info[-1]

    available_count = 0
    available_chars = {}
    ARTIFACTS_ATTRS[a["slotKey"]][a["mainStatKey"]].each do |ac|
        is_cor_set = ac["sets"].include? a["setKey"]
        # 花毛始终使用套件
        next if !is_cor_set && !CONFIG["allow_nonset_on_flower"] && %w(flower plume).include?(a["slotKey"])

        value = a["substats"].sum(0) do |x|
            next 0 if !ac["sub_attr"].include? x["key"]
            _v = (x["value"] / SUB_STAT_BASE_VALUES[x["key"]][a["rarity"]]).ceil
            # 计算副词条价值，小词条计0.5
            %w(atk def hp).include?(x["key"]) ? _v.to_f / 2 : _v
        end

        mainStatKey = a["mainStatKey"].match(/^[a-z]+_dmg_$/) ? "ele_dmg_" : a["mainStatKey"]
        _avail = ac["sub_attr"] - [mainStatKey]
        threshold = CONFIG["#{"sub" if !is_cor_set}least_of_#{a["slotKey"]}_#{mainStatKey}"]
        # 根据有效词条种数调整阈值
        level_inc = a["level"] / 4 * (ac["threshold"] < 1 ? 0.5 : 1)
        threshold = [threshold, ac["threshold"]].min + level_inc
        threshold += 1 if !is_cor_set && ac["multi"]

        available_chars[ac["char"]] ||= {}
        available_chars[ac["char"]]["text"] = "#{value}/#{threshold}"
        available_chars[ac["char"]]["corset"] = is_cor_set
        available_chars[ac["char"]]["valuable"] = value >= threshold
        available_count += 1 if value >= threshold
    end
    lock_pending = available_count > 0 && !a["lock"] ||
        FORCE_UNLOCK && a["lock"] && available_count == 0
    info[-1] = lock_pending
    lock_artifacts.push i if lock_pending
    result_table.write_row i + 2, 0, info
    chars_requirements.keys.each_with_index do |c,j|
        next if !available_chars[c]
        result_table.write i + 2, j + CSV_PREFIX.length, available_chars[c]["text"]
        cell_format = {}
        cell_format.merge! format_corset if available_chars[c]["corset"]
        cell_format.merge! format_useful if available_chars[c]["valuable"]
        result_table.update_format_with_params i + 2, j + CSV_PREFIX.length, cell_format
    end
end

result_file.close
File.write "yas/lock.json", lock_artifacts.to_json
puts "lock-pending artifacts count: #{lock_artifacts.length}"
