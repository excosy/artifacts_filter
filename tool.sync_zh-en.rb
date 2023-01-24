require "csv"
require "json"
path_zh = "config/zh-cn.artifacts_equip.csv"
equip_zh = CSV.read(path_zh, headers: true)
AS_EQUAL = {
    atk_: %w(角斗士的终幕礼 来歆余响 辰砂往生录 追忆之注连),
    eleMas: %w(流浪大地的乐团 饰金之梦 乐园遗落之花),
    anemo_dmg_: %w(翠绿之影 沙上楼阁史话),
    physical_dmg_: %w(染血的骑士道 苍白之火),
}
equip_zh.each do |x|
    AS_EQUAL.values.each do |a|
        t = a.any? { |y| x[y].to_i == 2 }
        a.each { |y| x[y] = 2 if !x[y] } if t
    end
end
zh_headers = File.readlines(path_zh)[0].strip
zh_bodies = equip_zh.map{|x| equip_zh.headers.map{|y| x[y]}.join(",")}.join("\r\n")
File.write path_zh, zh_headers + "\r\n" + zh_bodies + "\r\n"

locale_zh = `ls locales/zh-cn.*.json`.split.reduce({}) { |r,f| r.merge JSON.load_file!(f) }
locale_en = `ls locales/en-us.*.json`.split.reduce({}) { |r,f| r.merge JSON.load_file!(f) }
locale_zh_en = {}
locale_zh.keys.each {|x| locale_zh_en[locale_zh[x]] = locale_en[x] }
path_en = "config/en-us.artifacts_equip.csv"
en_headers = zh_headers.split(",").map{|x| locale_zh_en[x] || x}.join(",")
en_bodies = equip_zh.map{|r| equip_zh.headers.map{|x| locale_zh_en[r[x]] || r[x]}.join(",")}.join("\r\n")
File.write path_en, en_headers + "\r\n" + en_bodies + "\r\n"
