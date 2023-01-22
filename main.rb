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
ARTIFACTS_SETS = JSON.load_file! "locales/#{CONFIG["locale"]}.artifacts_sets.json"
CHAR_CONFIG = CSV.read "config/#{CONFIG["locale"]}.artifacts_equip.csv", headers: true

# 根据人物主堆属性确定各主属性下属词条
CHAR_CONFIG.each do |c|
    next if c["enable"].upcase != "TRUE"

    c_attr = {
        "sub_attr" => [],
        "main_attr" => {
            "flower" => ["hp"],
            "plume" => ["atk"],
            "sands" => [],
            "goblet" => [],
            "circlet" => [],
        },
        "multi" => false,
        "detail" => "",
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

    c_attr["main_attr"]["sands"] += ["enerRech_"] if c["ER"].to_i > 1
    c_attr["sub_attr"] += ["enerRech_"] if c["ER"].to_i > 0

    c_attr["main_attr"]["goblet"] << KEY_MAIN_ATTR[c["elem"]] if KEY_MAIN_ATTR[c["elem"]]

    case c["CR"].to_i
    when -1 then c_attr["sub_attr"] += ["heal_"]
    when 1
        c_attr["sub_attr"] += ["critRate_"]
        c_attr["main_attr"]["circlet"] += ["critRate_"]
    when 2
        c_attr["sub_attr"] += ["critDMG_"]
        c_attr["main_attr"]["circlet"] += ["critDMG_"]
    when 3
        c_attr["sub_attr"] += ["critRate_", "critDMG_"]
        c_attr["main_attr"]["circlet"] += ["critRate_", "critDMG_"]
    end

    cm = ["sands", "goblet", "circlet"].map do |x|
        if CONFIG["allow_substitution"] || !c_attr["main_attr"][x]
            c_attr["main_attr"][x] << KEY_MAIN_ATTR[c["mainAttr"]]
            c_attr["main_attr"][x] << KEY_MAIN_ATTR[c["mainAttr2"]] if KEY_MAIN_ATTR[c["mainAttr2"]]
            c_attr["main_attr"][x].uniq!
        end
        c_attr["main_attr"][x].map{|x| LOC_ATTRS[x]}.uniq.join(",")
    end
    c_attr["sub_attr"].uniq!
    cs = c_attr["sub_attr"].map{|x| LOC_ATTRS[x]}.uniq.join(",")
    c_attr["detail"] = "#{LOC_LOG["main_attrs"]}: #{cm.join(";")}\t#{LOC_LOG["sub_attrs"]}: #{cs}"

    ARTIFACTS_SETS.each do |k,v|
        next if !c[v]

        as_attr = {
            "sets" => k,
            "sub_attr" => c_attr["sub_attr"],
            "multi" => c_attr["multi"],
            "comment" => "#{c["char"]}-#{c["mainAttr"]}-#{v}",
            "detail" => c_attr["detail"],
        }

        c_attr["main_attr"].each do |s,t|
            t.uniq.each do |a|
                ARTIFACTS_ATTRS[s][a] ||= []
                ARTIFACTS_ATTRS[s][a] << as_attr
            end
        end
    end
end

SUB_STAT_BASE_VALUES = {
    "hp" => [1, 29.88, 71.70, 143.40, 239.00, 298.75],
    "atk" => [1, 1.95, 4.67, 9.34, 15.56, 19.45],
    "def" => [1, 2.31, 5.56, 11.11, 18.52, 23.15],
    "hp_" => [1, 1.46, 2.33, 3.50, 4.66, 5.83],
    "atk_" => [1, 1.46, 2.33, 3.50, 4.66, 5.83],
    "def_" => [1, 1.82, 2.91, 4.37, 5.83, 7.29],
    "eleMas" => [1, 5.83, 9.33, 13.99, 18.56, 23.31],
    "enerRech_" => [1, 1.62, 2.59, 3.89, 5.18, 6.48],
    "critRate_" => [1, 0.97, 1.55, 2.33, 3.11, 3.89],
    "critDMG_" => [1, 1.94, 3.11, 4.66, 6.22, 7.77],
}
# 计算价值并根据设置决定圣遗物去留
FORCE_UNLOCK = ARGV.include? "-f"
artifacts_log = File.open("yas/artifacts.log","w")
lock_artifacts = []
JSON.load_file!("yas/good.json")["artifacts"].each_with_index do |a,i|
    artifacts_log.puts "====================================================="
    info = "No.#{i+1}: #{ARTIFACTS_SETS[a["setKey"]]}-#{LOC_LOG[a["slotKey"]]}"
    info += "\t#{LOC_LOG["main_attrs"]}: #{LOC_ATTRS[a["mainStatKey"]]}"
    info += "\t#{LOC_LOG["sub_attrs"]}: #{a["substats"].map{|x| LOC_ATTRS[x["key"]]}.join(",")}"
    info += "\t#{LOC_LOG["level>1"]}" if a["level"].to_i > 1
    artifacts_log.puts info

    artifacts_log.puts LOC_LOG["locked"] and next if a["lock"] && !FORCE_UNLOCK
    if !ARTIFACTS_SETS[a["setKey"]]
        artifacts_log.puts LOC_LOG["not_registered"] % {lang: CONFIG["locale"]}
        next
    end
    if !ARTIFACTS_ATTRS[a["slotKey"]][a["mainStatKey"]]
        artifacts_log.puts LOC_LOG["inavailable_main_attr"]
        next
    end

    available_count = 0
    ARTIFACTS_ATTRS[a["slotKey"]][a["mainStatKey"]].each do |ac|
        value = a["substats"].sum(0) do |x|
            next 0 if !ac["sub_attr"].include? x["key"]
            _v = (x["value"] / SUB_STAT_BASE_VALUES[x["key"]][a["rarity"]]).ceil
            # 计算副词条价值，小词条计0.5
            ["atk","def","hp"].include?(x) ? _v / 2 : _v
        end

        # 初始词条不满时价值+0.5
        value += 0.5 if a["substats"].length < a["rarity"].to_i - 1
        a["mainStatKey"] = "ele_dmg_" if a["mainStatKey"].match /^\w+_dmg_$/
        threshold = if ac["sets"] == a["setKey"]
                CONFIG["least_of_#{a["slotKey"]}_#{a["mainStatKey"]}"]
            else
                CONFIG["subleast_of_#{a["slotKey"]}_#{a["mainStatKey"]}"]
            end
        # 有效词条不足4时减少阈值
        if ac["sets"] == a["setKey"] && ac["sub_attr"].length < 5
            threshold = [threshold, ac["sub_attr"].length - 1].min
            threshold += (a["level"] / 4 * (ac["sub_attr"].length - 1) / 4.0).ceil
        else
            threshold += a["level"] / 4
        end
        threshold += 1 if ac["sets"] != a["setKey"] && ac["multi"]
        if value >= threshold
            artifacts_log.puts "-----------------------------------------------------"
            artifacts_log.puts LOC_LOG["value_comment"] % {set: ac["comment"], val: value}
            artifacts_log.puts "#{LOC_LOG["set_requirements"]}: #{ac["detail"]}"
            artifacts_log.puts "#{LOC_LOG["slot_threshold"]}: #{threshold}"
            available_count += 1
        end
    end
    if available_count > 0
        lock_artifacts << i if !a["lock"]
    else
        lock_artifacts << i if FORCE_UNLOCK && a["lock"]
        artifacts_log.puts LOC_LOG["worthless"]
    end
end

artifacts_log.close
File.write "yas/lock.json", lock_artifacts.to_json
puts "lock-pending artifacts count: #{lock_artifacts.length}"
