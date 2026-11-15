class_name MissionValidator
extends RefCounted

## Modüler NASA görev doğrulama ve sonuç değerlendirme motoru.
## Tüm kurallar data/missions.json ve data/parts_catalog.json içindeki
## deklaratif alanlardan (requirements, tags, limitler) okunur.

static func collect_installed_tags(installed_parts: Array) -> Dictionary:
	var tag_counts: Dictionary = {}
	for part in installed_parts:
		var tags: Array = part.get("tags", [])
		for t in tags:
			var key: String = String(t)
			tag_counts[key] = int(tag_counts.get(key, 0)) + 1
	return tag_counts

static func get_launch_site_penalty(mission: Dictionary, launch_site: Dictionary) -> Dictionary:
	var mission_id: String = String(mission.get("id", ""))
	var penalties: Dictionary = launch_site.get("penalty_by_mission", {})
	if penalties.has(mission_id):
		return penalties[mission_id]
	return { "mass_penalty_kg": 0.0, "cost_penalty_m": 0, "note": "" }

static func validate_build(
	mission: Dictionary,
	rocket: Dictionary,
	launch_site: Dictionary,
	installed_parts: Array,
	total_mass_kg: float,
	net_power_w: float,
	power_cycling_enabled: bool = false,
	junocam_degraded: bool = false,
	power_lab_decided: bool = true,
	briefing_completed: bool = true
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if not briefing_completed:
		errors.append("BRİFİNG EKSİK: Fırlatma öncesi 1. Brifing Odası terminalinden görev brifingini tamamlayın!")

	if not power_lab_decided:
		errors.append("GÜÇ LAB KARARI EKSİK: Fırlatma öncesi Güç & Termal Lab terminalinden güç konfigürasyonunu seçin!")

	var site_penalty: Dictionary = get_launch_site_penalty(mission, launch_site)
	var effective_mass_kg: float = total_mass_kg + float(site_penalty.get("mass_penalty_kg", 0.0))
	if float(site_penalty.get("mass_penalty_kg", 0.0)) > 0.0:
		warnings.append(String(site_penalty.get("note", "Fırlatma üssü yörünge cezası uygulanıyor.")))

	var rocket_cap: float = float(rocket.get("max_mass_kg", 0.0))
	var mission_max_mass: float = float(mission.get("max_mass_kg", 999999.0))
	if rocket.is_empty() or rocket_cap <= 0.0:
		rocket_cap = mission_max_mass
	if effective_mass_kg > rocket_cap:
		errors.append("Roket kapasitesi aşıldı: %.1f kg / %.1f kg (%s)" % [
			effective_mass_kg, rocket_cap, String(rocket.get("name", "Roket"))
		])
	if rocket_cap > mission_max_mass * 5.0:
		errors.append("GÖREV UYUMSUZLUĞU: %s (%.0f kg) bu görevin yük sınıfına uygun değil (aşırı büyük roket)!" % [
			String(rocket.get("name", "Seçili roket")), rocket_cap
		])
	elif rocket_cap > mission_max_mass * 1.5:
		warnings.append("Ağır sınıf roket kullanılıyor; ekstra bütçe harcandı.")

	var distance_au: float = float(mission.get("distance_au", 1.0))
	if distance_au > 1.2 and not bool(rocket.get("deep_space", false)):
		errors.append("%s derin uzay görevine uygun değil!" % String(rocket.get("name", "Seçili roket")))

	if net_power_w < 0.0:
		errors.append("Güç bütçesi yetersiz: %.1f W açık var!" % abs(net_power_w))
	elif net_power_w < 20.0:
		warnings.append("Güç marjı çok düşük (%.1f W). Gölge/kriz anında kesinti yaşanabilir." % net_power_w)

	if bool(mission.get("requires_power_cycling", false)):
		for part in installed_parts:
			var peak_w: float = float(part.get("peak_power_w", 0.0))
			if peak_w > float(mission.get("nominal_power_w", 0.0)):
				if not power_cycling_enabled:
					errors.append("MÜHENDİSLİK TUZAĞI: %s anlık %.0f W çeker (MMRTG sınırı %.0f W)! Güç Lab'da Power Cycling / Batarya Tamponu açılmadan sistem çöker!" % [
						String(part.get("name", "MOXIE")), peak_w, float(mission.get("nominal_power_w", 0.0))
					])
				else:
					warnings.append("%s (%.0f W tepe yük) Power Cycling batarya tamponu ile sıralı çalıştırılıyor." % [
						String(part.get("name", "MOXIE")), peak_w
					])

	var tags: Dictionary = collect_installed_tags(installed_parts)
	if tags.has("radiation_degrading_camera"):
		if junocam_degraded:
			warnings.append("JunoCam radyasyon bozulması aktif: Jüpiter radyasyonunda sensör pikselleri bozuluyor (-%35 kamera verimi).")
		else:
			warnings.append("JunoCam radyasyon kuşağında birkaç yörünge sonra bozulmaya uğrayabilir; Termal Tavlama veya Zırh hazırda tutulmalı.")

	return {
		"can_launch": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"effective_mass_kg": effective_mass_kg,
		"power_margin_w": net_power_w
	}

static func evaluate_requirements(mission: Dictionary, installed_parts: Array) -> Array[String]:
	var failures: Array[String] = []
	var tags: Dictionary = collect_installed_tags(installed_parts)
	var requirements: Array = mission.get("requirements", [])

	for req in requirements:
		var req_type: String = String(req.get("type", ""))
		match req_type:
			"require_tag":
				var tag: String = String(req.get("tag", ""))
				if not tags.has(tag):
					failures.append(String(req.get("fail_reason", "Zorunlu sistem eksik: " + tag)))
			"require_any_tag":
				var any_tags: Array = req.get("tags", [])
				var found: bool = false
				for t in any_tags:
					if tags.has(String(t)):
						found = true
						break
				if not found:
					failures.append(String(req.get("fail_reason", "Gerekli sensör grubundan cihaz seçilmedi.")))
			"forbid_only_tag":
				var only_tag: String = String(req.get("only_tag", ""))
				var unless_tags: Array = req.get("unless_tags", [])
				if tags.has(only_tag):
					var has_support: bool = false
					for u in unless_tags:
						if tags.has(String(u)):
							has_support = true
							break
					if not has_support:
						failures.append(String(req.get("fail_reason", "Tek başına yetersiz cihaz seçimi.")))

	return failures

static func evaluate_mission_outcome(
	mission: Dictionary,
	rocket: Dictionary,
	launch_site: Dictionary,
	installed_parts: Array,
	total_mass_kg: float,
	net_power_w: float,
	science_score: int,
	downloaded_data_gb: float,
	landing_success_chance: int,
	budget_mult_score: float = 1.0,
	power_cycling_enabled: bool = false,
	junocam_degraded: bool = false,
	purchased_parts: Array = [],
	power_lab_decided: bool = true,
	briefing_completed: bool = true,
	budget_m: float = 0.0
) -> Dictionary:
	var build_check: Dictionary = validate_build(
		mission,
		rocket,
		launch_site,
		installed_parts,
		total_mass_kg,
		net_power_w,
		power_cycling_enabled,
		junocam_degraded,
		power_lab_decided,
		briefing_completed
	)
	var req_failures: Array[String] = evaluate_requirements(mission, installed_parts)

	var errors: Array[String] = []
	if budget_m < 0.0:
		errors.append("BÜTÇE AŞIMI: Bütçe eksiye düştü ($%.0fM)!" % budget_m)
	errors.append_array(build_check["errors"])
	errors.append_array(req_failures)

	var warnings: Array[String] = build_check["warnings"]
	var target_science: int = int(mission.get("target_science", 500))
	if science_score < target_science:
		warnings.append("Hedef bilim puanına ulaşılamadı (%d / %d)." % [science_score, target_science])

	var buy_counts: Dictionary = {}
	var buy_names: Dictionary = {}
	for p in purchased_parts:
		var pid: String = String(p.get("id", ""))
		if pid == "":
			continue
		buy_counts[pid] = int(buy_counts.get(pid, 0)) + 1
		buy_names[pid] = String(p.get("name", pid))
	for pid in buy_counts.keys():
		var cnt: int = int(buy_counts[pid])
		if cnt > 1:
			warnings.append("%d kere aynı ekipman satın alındı: %s (Ekstra bütçe harcandı, yalnızca 1 adet monte edilebilir!)" % [
				cnt, String(buy_names[pid])
			])

	var success: bool = errors.is_empty() and landing_success_chance >= 60
	if errors.is_empty() and landing_success_chance < 60:
		errors.append("İniş/operasyon başarı oranı yetersiz kaldı (%%%d — en az %%60 gerekli)." % landing_success_chance)

	var final_score: int = 0
	if success:
		final_score = int(round((science_score + downloaded_data_gb * 10.0) * budget_mult_score))

	var report: Dictionary = {
		"success": success,
		"score": final_score,
		"science_score": science_score,
		"downloaded_data_gb": downloaded_data_gb,
		"errors": errors,
		"warnings": warnings,
		"summary": "GÖREV BAŞARILI" if success else "GÖREV BAŞARISIZ"
	}
	return report
