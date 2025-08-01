public class Tuba.Views.Notifications : Views.Timeline, AccountHolder, Streamable {
	protected InstanceAccount? last_account = null;
	private Binding badge_number_binding;
	private Binding filtered_notifications_count_binding;
	private Adw.Banner notifications_filter_banner;
	private bool enabled_group_notifications = false;

	public int32 filtered_notifications {
		set {
			if (notifications_filter_banner == null) return;

			if (value > 0) {
				notifications_filter_banner.title = GLib.ngettext (
					"%d Filtered Notification",
					"%d Filtered Notifications",
					(ulong) value
				).printf (value);
				notifications_filter_banner.revealed = true;
			} else {
				notifications_filter_banner.revealed = false;
			}
		}
	}

	private bool is_all {
		set {
			if (value) {
				this.add_css_class ("notifications-all");
			} else {
				this.remove_css_class ("notifications-all");
			}
		}
	}

	construct {
		enabled_group_notifications = accounts.active.tuba_api_versions.mastodon >= 2 || InstanceAccount.InstanceFeatures.GROUP_NOTIFICATIONS in accounts.active.tuba_instance_features;
		url = @"/api/v$(enabled_group_notifications ? 2 : 1)/notifications";
		label = _("Notifications");
		icon = "tuba-bell-outline-symbolic";
		accepts = enabled_group_notifications ? typeof (API.GroupedNotificationsResults.NotificationGroup) : typeof (API.Notification);
		badge_number = 0;
		needs_attention = false;
		empty_state_title = _("No Notifications");

		filters_changed (false);
		stream_event[InstanceAccount.EVENT_NOTIFICATION].connect (on_new_post);
		stream_event[InstanceAccount.EVENT_NOTIFICATIONS_MERGED].connect (on_refresh);
		stream_event[InstanceAccount.EVENT_EDIT_POST].connect (on_edit_post);
		stream_event[InstanceAccount.EVENT_DELETE_POST].connect (on_delete_post);

		#if DEV_MODE
			app.dev_new_notification.connect (node => {
				try {
					model.insert (0, Entity.from_json (accepts, node));
				} catch (Error e) {
					warning (@"Error getting Entity from json: $(e.message)");
				}
			});
		#endif

		notifications_filter_banner = new Adw.Banner ("") {
			use_markup = true,
			button_label = _("View"),
			revealed = false
		};
		notifications_filter_banner.button_clicked.connect (on_notifications_filter_banner_button_clicked);

		var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
			vexpand = true
		};
		box.append (notifications_filter_banner);
		scrolled_overlay.child = box;
		box.append (states);

		settings.notify["dim-trivial-notifications"].connect (settings_updated);
		settings_updated ();

		app.notify["is-online"].connect (on_network_change);
	}

	protected override void on_scrolled_vadjustment_value_change () {
		base.on_scrolled_vadjustment_value_change ();

		if (scrolled.vadjustment.value <= 50 && account != null && account.unread_count > 0) {
			account.read_notifications (
				account.last_received_id > account.last_read_id
					? account.last_received_id
					: account.last_read_id
			);
		}
	}

	private void on_network_change () {
		if (app.is_online && account != null && account.unread_count > 0 && app.main_window.is_home) {
			on_refresh ();
		}
	}

	private void settings_updated () {
		Tuba.toggle_css (this, settings.dim_trivial_notifications, "dim-enabled");
	}

	private void on_notifications_filter_banner_button_clicked () {
		app.main_window.open_view (new Views.NotificationRequests ());
	}

	public override bool should_hide (Entity entity) {
		var notification_entity = entity as API.Notification;
		if (notification_entity != null && notification_entity.status != null) {
			return base.should_hide (notification_entity.status);
		}

		return false;
	}

	~Notifications () {
		warning ("Destroying Notifications");
		stream_event[InstanceAccount.EVENT_NOTIFICATION].disconnect (on_new_post);
		badge_number_binding.unbind ();
	}

	public override void on_account_changed (InstanceAccount? acc) {
		enabled_group_notifications = acc.tuba_api_versions.mastodon >= 2 || InstanceAccount.InstanceFeatures.GROUP_NOTIFICATIONS in acc.tuba_instance_features;
		accepts = enabled_group_notifications ? typeof (API.GroupedNotificationsResults.NotificationGroup) : typeof (API.Notification);
		filters_changed (false);
		base.on_account_changed (acc);

		if (badge_number_binding != null)
			badge_number_binding.unbind ();

		if (filtered_notifications_count_binding != null)
			filtered_notifications_count_binding.unbind ();

		badge_number_binding = accounts.active.bind_property (
			"unread-count",
			this,
			"badge-number",
			BindingFlags.SYNC_CREATE,
			(b, src, ref target) => {
				var unread_count = src.get_int ();
				target.set_int (unread_count);
				this.needs_attention = unread_count > 0;
				Tuba.Mastodon.Account.PLACE_NOTIFICATIONS.badge = unread_count;

				return true;
			}
		);

		filtered_notifications_count_binding = accounts.active.bind_property (
			"filtered-notifications-count",
			this,
			"filtered-notifications",
			BindingFlags.SYNC_CREATE,
			on_filtered_notifications_count_change
		);
	}

	private bool on_filtered_notifications_count_change (Binding binding, Value from_value, ref Value to_value) {
		to_value.set_int (from_value.get_int ());
		return true;
	}

	public override void on_shown () {
		base.on_shown ();
		if (account != null) {
			account.read_notifications (
				account.last_received_id > account.last_read_id
					? account.last_received_id
					: account.last_read_id
			);

			if (account.tuba_probably_has_notification_filters)
				update_filtered_notifications ();
		}
	}

	public override void on_hidden () {
		base.on_hidden ();
		if (account != null) {
			account.unread_count = 0;
		}
	}

	public override bool request () {
		if (!enabled_group_notifications) return base.request ();

		append_params (new Request.GET (get_req_url ()))
			.with_account (account)
			.with_ctx (this)
			.with_extra_data (Tuba.Network.ExtraData.RESPONSE_HEADERS)
			.then ((in_stream, headers) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var node = network.parse_node (parser);
				if (node == null) return;

				Object[] to_add = {};
				var group_notifications = API.GroupedNotificationsResults.from (node);
				foreach (var group in group_notifications.notification_groups) {
					Gee.ArrayList<API.Account> group_accounts = new Gee.ArrayList<API.Account> ();
					foreach (var account in group_notifications.accounts) {
						if (account.id in group.sample_account_ids)
							group_accounts.add (account);
					}
					group.tuba_accounts = group_accounts;

					if (group.tuba_accounts.size == 1) {
						group.account = group.tuba_accounts.get (0);
					}

					if (group.status_id != null) {
						foreach (var status in group_notifications.statuses) {
							if (status.id == group.status_id) {
								group.status = status;
								break;
							}
						}
					}

					// filtering is based on the status
					// so it can only happen after the above
					if (!(should_hide (group))) to_add += group;
				}
				model.splice (model.get_n_items (), 0, to_add);

				if (headers != null)
					get_pages (headers.get_one ("Link"));

				if (to_add.length == 0)
					on_content_changed ();
				on_request_finish ();
			})
			.on_error (on_error)
			.exec ();

		return GLib.Source.REMOVE;
	}

	public void update_filtered_notifications () {
		new Request.GET ("/api/v1/notifications/policy")
			.with_account (accounts.active)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var node = network.parse_node (parser);
				if (node == null) {
					accounts.active.filtered_notifications_count = 0;
					return;
				};

				var policies = API.NotificationFilter.Policy.from (node);
				if (policies.summary != null) {
					accounts.active.filtered_notifications_count = policies.summary.pending_notifications_count;
				}
			})
			.on_error ((code, message) => {
				accounts.active.filtered_notifications_count = 0;
				if (code == 404) {
					accounts.active.tuba_probably_has_notification_filters = false;
				} else {
					warning (@"Error while trying to get notification policy: $code $message");
				}
			})
			.exec ();
	}

	public override string? get_stream_url () {
		return account != null
			? @"$(account.instance)/api/v1/streaming?stream=user:notification&access_token=$(account.access_token)"
			: null;
	}

	public static string get_notifications_excluded_types_query_param () {
		if (settings.notification_filters.length == 0) return "";

		return @"?exclude_types[]=$(string.joinv ("&exclude_types[]=", settings.notification_filters))";
	}

	public void filters_changed (bool refresh = true) {
		string new_url = @"/api/v$(enabled_group_notifications ? 2 : 1)/notifications";

		if (settings.notification_filters.length == 0) {
			this.is_all = true;
		} else {
			this.is_all = false;
			new_url += get_notifications_excluded_types_query_param ();
		}

		if (new_url == this.url) return;
		this.url = new_url;

		if (refresh) {
			page_next = null;
			on_refresh ();
		}
	}

	public override void on_new_post (Streamable.Event ev) {
		try {
			var entity = (API.Notification) Entity.from_json (typeof (API.Notification), ev.get_node ());
			if (
				settings.notification_filters.length > 0
				&& entity.kind in settings.notification_filters
			) return;

			if (enabled_group_notifications && entity.group_key != null && !entity.group_key.has_prefix ("ungrouped-")) {
				API.GroupedNotificationsResults.NotificationGroup? group = null;
				for (uint i = 0; i < model.get_n_items (); i++) {
					var notification_obj = model.get_item (i) as API.GroupedNotificationsResults.NotificationGroup;
					if (notification_obj != null && notification_obj.group_key == entity.group_key) {
						group = notification_obj;
						model.remove (i);
						break;
					}
				}

				if (group != null) {
					group.patch (entity);
					//  group.most_recent_notification_id = entity.id;

					if (group.tuba_accounts == null) group.tuba_accounts = new Gee.ArrayList<API.Account> ();
					group.tuba_accounts.insert (0, entity.account);

					if (group.sample_account_ids == null) group.sample_account_ids = new Gee.ArrayList<string> ();
					group.sample_account_ids.insert (0, entity.account.id);
					on_new_post_entity (group);
				} else {
					on_new_post_entity (new API.GroupedNotificationsResults.NotificationGroup.from_notification (entity));
				}
			} else {
				on_new_post_entity (entity);
			}

		} catch (Error e) {
			warning (@"Error getting Entity from json: $(e.message)");
		}
	}

	public override void on_edit_post (Streamable.Event ev) {
		try {
			var entity = Entity.from_json (typeof (API.Status), ev.get_node ()) as API.Status;
			if (entity == null) return;

			var entity_id = entity.id;
			for (uint i = 0; i < model.get_n_items (); i++) {
				var notification_obj = model.get_item (i) as API.Notification;
				if (notification_obj != null && notification_obj.status != null && notification_obj.status.id == entity_id) {
					model.remove (i);
					notification_obj.status = entity;
					model.insert (i, notification_obj);
				}
			}
		} catch (Error e) {
			warning (@"Error getting Entity from json: $(e.message)");
		}
	}

	public override void on_delete_post (Streamable.Event ev) {
		try {
			var status_id = ev.get_string ();

			for (uint i = 0; i < model.get_n_items (); i++) {
				var notification_obj = model.get_item (i) as API.Notification;
				if (notification_obj != null && notification_obj.status != null && notification_obj.status.formal.id == status_id) {
					model.remove (i);
				}
			}
		} catch (Error e) {
			warning (@"Error getting String from json: $(e.message)");
		}
	}
}
