require "json"
require "csv"

CONFIG = JSON.load_file! "config/artifacts_config.json"
LOC_ATTRS = JSON.load_file! "locales/#{CONFIG["locale"]}.attributes.json"
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
artifacts_requirements = {}
chars_requirements = {}

# 根据人物主堆属性确定各主属性下属词条
CHAR_CONFIG.each do |c|
    next if c["enable"].upcase != "TRUE" || DISABLED_CHARS.include?(c["char"])

    c_attr = {
        "char" => c["char"],
        "sub_attr" => [],
        "multi" => false,
        "detail" => "",
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
    c_attr["multi"] = true if (c_attr["sub_attr"] & ["atk","def","hp"]).length > 1

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

    cm = ["sands", "goblet", "circlet"].map do |x|
        if CONFIG["allow_substitution"] || !main_attr[x]
            main_attr[x] << KEY_MAIN_ATTR[c["mainAttr"]]
            main_attr[x] << KEY_MAIN_ATTR[c["mainAttr2"]] if KEY_MAIN_ATTR[c["mainAttr2"]]
            main_attr[x].uniq!
        end
        main_attr[x].map{|x| LOC_ATTRS[x]}.uniq.join(",")
    end
    c_attr["sub_attr"].uniq!
    cs = c_attr["sub_attr"].map{|x| LOC_ATTRS[x]}.uniq.join(",")
    c_attr["detail"] = "#{LOC_LOG["main_attrs"]}: #{cm.join("; ")}\t#{LOC_LOG["sub_attrs"]}: #{cs}"

    artifacts_requirements[c_attr["char"]] = c_attr
    chars_requirements[c_attr["char"]] = {
        "sets" => c_attr["sets"].map{|x| LOC_ARTIFACTS[x]},
        "sub_attr" => c_attr["sub_attr"].map{|x| LOC_ATTRS[x]}.uniq
    }
    main_attr.each do |s,t|
        t.uniq.each do |a|
            ARTIFACTS_ATTRS[s][a] ||= []
            ARTIFACTS_ATTRS[s][a] << c_attr
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
log_artifacts_detail = File.open("yas/artifacts.detail.csv","w")
log_artifacts_detail << "\xEF\xBB\xBF"
CSV_PREFIX = %w[No. setName slotName level mainAttr subAttr availableCount]
log_artifacts_detail.puts (CSV_PREFIX + chars_requirements.keys).join(",")
sec_prefix = [LOC_LOG["sub_attrs"], LOC_LOG["detail_note"]] + [nil] * (CSV_PREFIX.length - 2)
sub_attrs = chars_requirements.values.map{|x| x["sub_attr"].join(" ")}
log_artifacts_detail.puts (sec_prefix + sub_attrs).join(",")
ALL_ARTIFACTS = JSON.load_file!("yas/good.json")["artifacts"]
ALL_ARTIFACTS.each_with_index do |a,i|
    info = [i, LOC_ARTIFACTS[a["setKey"]], LOC_LOG[a["slotKey"]], a["level"], LOC_ATTRS[a["mainStatKey"]]]
    info.push a["substats"].map{|x| LOC_ATTRS[x["key"]]}.join(" "), false
    info[-1] = LOC_LOG["set_not_used"] if !ARTIFACTS_ATTRS[a["slotKey"]]
    info[-1] = LOC_LOG["main_attr_not_used"] if !ARTIFACTS_ATTRS[a["slotKey"]][a["mainStatKey"]]
    next log_artifacts_detail.puts info.join(",") if info[-1]

    available_count = 0
    available_chars = {}
    ARTIFACTS_ATTRS[a["slotKey"]][a["mainStatKey"]].each do |ac|
        is_cor_set = ac["sets"].include? a["setKey"]
        # 花毛始终使用套件
        next if !is_cor_set && !CONFIG["allow_nonset_on_flower"] && (a["slotKey"] == "flower" || a["slotKey"] == "plume")

        value = a["substats"].sum(0) do |x|
            next 0 if !ac["sub_attr"].include? x["key"]
            _v = (x["value"] / SUB_STAT_BASE_VALUES[x["key"]][a["rarity"]]).ceil
            # 计算副词条价值，小词条计0.5
            ["atk","def","hp"].include?(x["key"]) ? _v.to_f / 2 : _v
        end

        mainStatKey = a["mainStatKey"].match(/^\w+_dmg_$/) ? "ele_dmg_" : a["mainStatKey"]
        threshold = CONFIG["#{"sub" if !is_cor_set}least_of_#{a["slotKey"]}_#{mainStatKey}"]
        # 根据有效词条种数调整阈值
        threshold = [threshold, ac["sub_attr"].length - 1].min
        _v = [ac["sub_attr"].length - 1, 4].min / 4.0
        threshold += (a["level"] / 4 * _v).ceil
        threshold += 1 if !is_cor_set && ac["multi"]

        available_chars[ac["char"]] = "#{value}/#{threshold}"
        if value >= threshold
            artifacts_requirements[ac["char"]]["artifacts"] ||= []
            artifacts_requirements[ac["char"]]["artifacts"] << {
                "no." => i, "value" => value, "threshold" => threshold
            }
            available_count += 1
        end
    end
    if available_count > 0
        lock_artifacts << i if !a["lock"]
    else
        lock_artifacts << i if FORCE_UNLOCK && a["lock"]
    end
    info[-1] = available_count
    info += chars_requirements.keys.map{|c| available_chars[c]}
    log_artifacts_detail.puts info.join(",")
end

log_artifacts_chars = File.open("yas/artifacts.chars.log", "w")
log_artifacts_chars << "\xEF\xBB\xBF"
artifacts_requirements.each do |c,ac|
    log_artifacts_chars.puts "\n====================================================="
    log_artifacts_chars.puts "#{c}\t\t#{ac["sets"].map{|x| LOC_ARTIFACTS[x]}.join(", ")}"
    log_artifacts_chars.puts "#{LOC_LOG["set_requirements"]}: #{ac["detail"]}"
    next if !ac["artifacts"]
    ac["artifacts"].each do |ai|
        a = ALL_ARTIFACTS[ai["no."]]
        log_artifacts_chars.puts "-----------------------------------------------------"
        info = "No.#{ai["no."]}: #{LOC_ARTIFACTS[a["setKey"]]}-#{LOC_LOG[a["slotKey"]]}"
        info += "\t#{LOC_LOG["main_attrs"]}: #{LOC_ATTRS[a["mainStatKey"]]}"
        info += "\t#{LOC_LOG["sub_attrs"]}: #{a["substats"].map{|x| LOC_ATTRS[x["key"]]}.join(",")}"
        info += "\nlv.#{a["level"]}\t#{LOC_LOG["value_comment"] % {val: ai["value"], thr: ai["threshold"]}}"
        log_artifacts_chars.puts info
    end
end
log_artifacts_chars.close
log_artifacts_detail.close
File.write "yas/lock.json", lock_artifacts.to_json
puts "lock-pending artifacts count: #{lock_artifacts.length}"
