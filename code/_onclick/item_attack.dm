
/obj/item/proc/melee_attack_chain(mob/user, atom/target, params)
	if(!tool_attack_chain(user, target) && pre_attack(target, user, params))
		// Return 1 in attackby() to prevent afterattack() effects (when safely moving items for example)
		var/resolved
		if(HAS_TRAIT(target, TRAIT_ONEWAYROAD))
			resolved = user.attackby(src, user, params) // you just hit yourself
		else
			resolved = target.attackby(src, user, params)
		if(!resolved && target && !QDELETED(src))
			 // 1: clicking something Adjacent
			if(HAS_TRAIT(target, TRAIT_ONEWAYROAD))
				afterattack(user, user, 1, params)
			else
				afterattack(target, user, 1, params)


//Checks if the item can work as a tool, calling the appropriate tool behavior on the target
/obj/item/proc/tool_attack_chain(mob/user, atom/target)
	if(!tool_behaviour)
		return FALSE

	return target.tool_act(user, src, tool_behaviour)


// Called when the item is in the active hand, and clicked; alternately, there is an 'activate held object' verb or you can hit pagedown.
/obj/item/proc/attack_self(mob/user)
	if(SEND_SIGNAL(src, COMSIG_ITEM_ATTACK_SELF, user) & COMPONENT_NO_INTERACT)
		return
	interact(user)

/obj/item/proc/pre_attack(atom/A, mob/living/user, params) //do stuff before attackby!
	if(SEND_SIGNAL(src, COMSIG_ITEM_PRE_ATTACK, A, user, params) & COMPONENT_NO_ATTACK)
		return FALSE
	return TRUE //return FALSE to avoid calling attackby after this proc does stuff

// No comment
/atom/proc/attackby(obj/item/W, mob/user, params)
	if(SEND_SIGNAL(src, COMSIG_PARENT_ATTACKBY, W, user, params) & COMPONENT_NO_AFTERATTACK)
		return TRUE
	return FALSE

/obj/attackby(obj/item/I, mob/living/user, params)
	return ..() || ((obj_flags & CAN_BE_HIT) && I.attack_obj(src, user))

/mob/living/attackby(obj/item/I, mob/living/user, params)
	if(..())
		return TRUE
	user.changeNext_move(CLICK_CD_MELEE)
	if(user.a_intent == INTENT_HARM && stat == DEAD && (butcher_results || guaranteed_butcher_results)) //can we butcher it?
		var/datum/component/butchering/butchering = I.GetComponent(/datum/component/butchering)
		if(butchering?.butchering_enabled)
			to_chat(user, "<span class='notice'>You begin to butcher [src]...</span>")
			playsound(loc, butchering.butcher_sound, 50, TRUE, -1)
			if(do_after(user, butchering.speed, src) && Adjacent(I))
				butchering.Butcher(user, src)
			return 1
		else if(I.is_sharp() && !butchering) //give sharp objects butchering functionality, for consistency
			I.AddComponent(/datum/component/butchering, 80 * I.toolspeed)
			attackby(I, user, params) //call the attackby again to refresh and do the butchering check again
			return
	return I.attack(src, user)


/obj/item/proc/attack(mob/living/M, mob/living/user)
	if(SEND_SIGNAL(src, COMSIG_ITEM_ATTACK, M, user) & COMPONENT_ITEM_NO_ATTACK)
		return
	SEND_SIGNAL(user, COMSIG_MOB_ITEM_ATTACK, M, user)
	SEND_SIGNAL(M, COMSIG_MOB_ITEM_ATTACKBY, user, src)

	var/nonharmfulhit = FALSE
	if(item_flags & NOBLUDGEON)
		nonharmfulhit = TRUE

	if(user.a_intent == INTENT_HELP && !(item_flags & ISWEAPON))
		nonharmfulhit = TRUE

	if(force && HAS_TRAIT(user, TRAIT_PACIFISM) && !nonharmfulhit)
		to_chat(user, "<span class='warning'>You don't want to harm other living beings!</span>")
		nonharmfulhit = TRUE

	if(!force || nonharmfulhit)
		playsound(loc, 'sound/weapons/tap.ogg', get_clamped_volume(), 1, -1)
	else if(hitsound)
		playsound(loc, hitsound, get_clamped_volume(), 1, -1)

	M.lastattacker = user.real_name
	M.lastattackerckey = user.ckey

	user.do_attack_animation(M)
	var/time = world.time
	if(nonharmfulhit)
		M.send_item_poke_message(src, user)
		user.time_of_last_poke = time
	else
		user.record_accidental_poking()
		M.attacked_by(src, user)
		M.time_of_last_attack_recieved = time
		user.time_of_last_attack_dealt = time
		user.check_for_accidental_attack()

	log_combat(user, M, "[nonharmfulhit ? "poked" : "attacked"]", src.name, "(INTENT: [uppertext(user.a_intent)]) (DAMTYPE: [uppertext(damtype)])")
	add_fingerprint(user)


//the equivalent of the standard version of attack() but for object targets.
/obj/item/proc/attack_obj(obj/O, mob/living/user)
	if(SEND_SIGNAL(src, COMSIG_ITEM_ATTACK_OBJ, O, user) & COMPONENT_NO_ATTACK_OBJ)
		return
	if(item_flags & NOBLUDGEON)
		return
	user.changeNext_move(CLICK_CD_MELEE)
	user.do_attack_animation(O)
	O.attacked_by(src, user)

/atom/movable/proc/attacked_by()
	return

/obj/attacked_by(obj/item/I, mob/living/user)
	if(I.force)
		user.visible_message("<span class='danger'>[user] hits [src] with [I]!</span>", \
					"<span class='danger'>You hit [src] with [I]!</span>", null, COMBAT_MESSAGE_RANGE)
		//only witnesses close by and the victim see a hit message.
		log_combat(user, src, "attacked", I)
	take_damage(I.force, I.damtype, MELEE, 1)

/mob/living/attacked_by(obj/item/I, mob/living/user)
	send_item_attack_message(I, user)
	if(I.force)
		apply_damage(I.force, I.damtype)
		if(I.damtype == BRUTE)
			if(prob(33))
				I.add_mob_blood(src)
				var/turf/location = get_turf(src)
				add_splatter_floor(location)
				if(get_dist(user, src) <= 1)	//people with TK won't get smeared with blood
					user.add_mob_blood(src)
		return TRUE //successful attack

/mob/living/simple_animal/attacked_by(obj/item/I, mob/living/user, nonharmfulhit = FALSE)
	if(I.force < force_threshold || I.damtype == STAMINA || nonharmfulhit)
		playsound(loc, 'sound/weapons/tap.ogg', I.get_clamped_volume(), 1, -1)
	else
		return ..()

// Proximity_flag is 1 if this afterattack was called on something adjacent, in your square, or on your person.
// Click parameters is the params string from byond Click() code, see that documentation.
/obj/item/proc/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	SEND_SIGNAL(src, COMSIG_ITEM_AFTERATTACK, target, user, proximity_flag, click_parameters)
	SEND_SIGNAL(user, COMSIG_MOB_ITEM_AFTERATTACK, target, user, proximity_flag, click_parameters)


/obj/item/proc/get_clamped_volume()
	if(w_class)
		if(force)
			return CLAMP((force + w_class) * 4, 30, 100)// Add the item's force to its weight class and multiply by 4, then clamp the value between 30 and 100
		else
			return CLAMP(w_class * 6, 10, 100) // Multiply the item's weight class by 6, then clamp the value between 10 and 100

/mob/living/proc/send_item_attack_message(obj/item/I, mob/living/user, hit_area)
	var/message_verb = "attacked"
	if(I.attack_verb && I.attack_verb.len)
		message_verb = "[pick(I.attack_verb)]"
	else if(!I.force)
		return
	var/message_hit_area = ""
	if(hit_area)
		message_hit_area = " in the [hit_area]"
	var/attack_message = "[src] is [message_verb][message_hit_area] with [I]!"
	var/attack_message_local = "You're [message_verb][message_hit_area] with [I]!"
	if(user in viewers(src))
		attack_message = "[user] [message_verb] [src][message_hit_area] with [I]!"
		attack_message_local = "[user] [message_verb] you[message_hit_area] with [I]!"
	if(user == src)
		attack_message_local = "You [message_verb] yourself[message_hit_area] with [I]!"
	visible_message("<span class='danger'>[attack_message]</span>",\
	"<span class='userdanger'>[attack_message_local]</span>", null, COMBAT_MESSAGE_RANGE)
	return 1

/mob/living/proc/send_item_poke_message(obj/item/I, mob/living/user)
	var/list/messages = list("poked", "prodded", "tapped", "nudged")
	var/message_verb = "[pick(messages)]"
	var/poke_message = "[src] is [message_verb] with [I]!"
	var/poke_message_local = "You're [message_verb] with [I]!"
	if(user in viewers(src))
		poke_message = "[user] [message_verb] [src] with [I]!"
		poke_message_local = "[user] [message_verb] you with [I]!"
	if(user == src)
		poke_message_local = "You [message_verb] yourself with [I]!"
	visible_message("<span class='notice'>[poke_message]</span>",\
	"<span class='usernotice'>[poke_message_local]</span>", null, COMBAT_MESSAGE_RANGE)

/mob/living/proc/record_accidental_poking()
	if(time_of_last_poke != 0 && world.time - time_of_last_poke <= 50)
		SSblackbox.record_feedback("tally", "poking_data", 1, "Hit someone shortly after poking them")

/mob/living/proc/check_for_accidental_attack()
	addtimer(CALLBACK(src, PROC_REF(record_accidental_attack), time_of_last_attack_dealt), 100, TIMER_OVERRIDE|TIMER_UNIQUE)

/mob/living/proc/record_accidental_attack(var/time)
	if(time_of_last_attack_dealt == 0) // We haven't attacked at all
		return
	if(time_of_last_attack_dealt > time) //We attacked again after the proc got called
		return
	//10 seconds passed after we last attacked someone - either it was an accident, or we robusted someone into being horizontal
	if(time_of_last_attack_dealt > time_of_last_attack_recieved + 100)
		SSblackbox.record_feedback("tally", "accidental_attack_data", 1, "Lasted ten seconds of not being hit after hitting somoene")
