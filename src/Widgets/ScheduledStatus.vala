public class Tuba.Widgets.ScheduledStatus : Gtk.ListBoxRow {
	public signal void deleted (string scheduled_status_id);
	public signal void refresh ();
	public signal void open ();

	private bool _draft = false;
	public bool draft {
		get { return _draft; }
		set {
			_draft = value;
			reschedule_button.visible = !value;
			// translators: not a verb, as in a post that is saved but not posted yet
			schedule_label.label = _("Draft");
			this.activatable = value;
		}
	}

	Gtk.Button reschedule_button;
	Gtk.Button edit_button;
	Gtk.Box content_box;
	Gtk.Label schedule_label;
	construct {
		this.focusable = true;
		this.activatable = false;
		this.css_classes = { "card-spacing", "card" };
		this.overflow = Gtk.Overflow.HIDDEN;

		content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
		var action_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
			margin_top = margin_bottom = margin_start = margin_end = 6
		};
		schedule_label = new Gtk.Label ("") {
			wrap = true,
			wrap_mode = Pango.WrapMode.WORD_CHAR,
			xalign = 0.0f,
			hexpand = true,
			margin_start = 6
		};
		action_box.append (schedule_label);

		var actions_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
		edit_button = new Gtk.Button.from_icon_name ("document-edit-symbolic") {
			css_classes = { "flat" },
			tooltip_text = _("Edit"),
			valign = Gtk.Align.CENTER
		};
		edit_button.clicked.connect (on_edit);
		actions_box.append (edit_button);

		reschedule_button = new Gtk.Button.from_icon_name ("tuba-clock-alt-symbolic") {
			tooltip_text = _("Reschedule"),
			css_classes = { "flat" }
		};
		reschedule_button.clicked.connect (on_reschedule);
		actions_box.append (reschedule_button);

		Gtk.Button delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
			css_classes = { "flat", "error" },
			tooltip_text = _("Delete"),
			valign = Gtk.Align.CENTER
		};
		delete_button.clicked.connect (on_delete);
		actions_box.append (delete_button);
		action_box.append (actions_box);

		content_box.append (action_box);
		content_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
		this.child = content_box;

		open.connect (on_activated);
	}

	public ScheduledStatus (API.ScheduledStatus scheduled_status) {
		Object ();
		bind (scheduled_status);
	}

	API.ScheduledStatus bound_scheduled_status;
	Widgets.Status? status_widget = null;
	API.Poll? status_poll = null;
	public void bind (API.ScheduledStatus scheduled_status) {
		if (status_widget != null) content_box.remove (status_widget);
		bound_scheduled_status = scheduled_status;

		GLib.DateTime now_load = new GLib.DateTime.now_local ();
		status_poll = null;
		if (scheduled_status.props.poll != null) {
			status_poll = new API.Poll ("0") {
				multiple = scheduled_status.props.poll.multiple,
				options = new Gee.ArrayList<API.PollOption> ()
			};

			foreach (string poll_option in scheduled_status.props.poll.options) {
				status_poll.options.add (new API.PollOption () {
					title = poll_option,
					votes_count = 0
				});
			}

			status_poll.expires_at = now_load.add_seconds (scheduled_status.props.poll.expires_in).format_iso8601 ();
		}

		var status = new API.Status.empty () {
			account = accounts.active,
			spoiler_text = scheduled_status.props.spoiler_text,
			content = scheduled_status.props.text,
			sensitive = scheduled_status.props.sensitive,
			visibility = scheduled_status.props.visibility,
			media_attachments = scheduled_status.media_attachments,
			tuba_spoiler_revealed = true,
			poll = status_poll,
			created_at = scheduled_status.scheduled_at
		};

		if (scheduled_status.props.language != null) status.language = scheduled_status.props.language;

		var widg = new Widgets.Status (status);
		widg.can_be_opened = false;
		widg.activatable = false;
		widg.actions.visible = false;
		widg.menu_button.visible = false;
		widg.date_label.visible = false;
		if (widg.poll != null) {
			widg.poll.usable = false;
			widg.poll.info_label.label = Utils.DateTime.humanize_ago (status_poll.expires_at);
		}

		// Re-parse the date into a MONTH DAY, YEAR (separator) HOUR:MINUTES
		var date_parsed = new GLib.DateTime.from_iso8601 (scheduled_status.scheduled_at, null);

		var delta = date_parsed.to_local ().difference (now_load);
		edit_button.visible = delta >= TimeSpan.HOUR;

		date_parsed = date_parsed.to_timezone (new TimeZone.local ());
		var date_local = _("%B %e, %Y");
		// translators: Scheduled Post title, 'scheduled for <date>'
		schedule_label.label = _("Scheduled for %s").printf (
			date_parsed.format (@"$date_local · %H:%M").replace (" ", "") // %e prefixes with whitespace on single digits
		);

		content_box.append (widg);
		status_widget = widg;
	}

	private class RescheduleDialog : Adw.Dialog {
		public signal void schedule_picked (string iso8601);

		public RescheduleDialog (string iso8601) {
			this.follows_content_size = true;

			var schedule_page = new Dialogs.Schedule (iso8601, _("Reschedule"));
			schedule_page.schedule_picked.connect (on_schedule_picked);

			var navigation_view = new Adw.NavigationView ();
			this.title = schedule_page.title = _("Reschedule Post");
			navigation_view.add (schedule_page);

			this.child = navigation_view;
		}

		private void on_schedule_picked (string iso8601) {
			schedule_picked (iso8601);
			this.force_close ();
		}
	}

	private void on_reschedule () {
		var dlg = new RescheduleDialog (bound_scheduled_status.scheduled_at);
		dlg.schedule_picked.connect (on_schedule_picked);
		dlg.present (app.main_window);
	}

	private void on_schedule_picked (string iso8601) {
		new Request.PUT (@"/api/v1/scheduled_statuses/$(bound_scheduled_status.id)")
			.with_account (accounts.active)
			.with_form_data ("scheduled_at", iso8601)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var node = network.parse_node (parser);
				var e = Tuba.Helper.Entity.from_json (node, typeof (API.ScheduledStatus), true);
				if (e is API.ScheduledStatus) bind ((API.ScheduledStatus) e);
			})
			.on_error ((code, message) => {
				warning (@"Error while rescheduling: $code $message");

				// translators: the variable is an error
				app.toast (_("Couldn't reschedule: %s").printf (message), 0);
			})
			.exec ();
	}

	private void on_delete () {
		string title = !_draft
			// translators: as in a post set to be posted sometime in the future
			? _("Delete Scheduled Post?")
			// translators: 'Draft' is not a verb here.
			//				It's equal to 'saved but not posted'
			: _("Delete Draft Post?");

		app.question.begin (
			{title, false},
			null,
			app.main_window,
			{ { _("Delete"), Adw.ResponseAppearance.DESTRUCTIVE }, { _("Cancel"), Adw.ResponseAppearance.DEFAULT } },
			null,
			false,
			(obj, res) => {
				if (app.question.end (res).truthy ()) {
					delete_status ();
				}
			}
		);
	}

	private void delete_status () {
		new Request.DELETE (@"/api/v1/scheduled_statuses/$(bound_scheduled_status.id)")
			.with_account (accounts.active)
			.then (() => {
				deleted (bound_scheduled_status.id);
			})
			.on_error ((code, message) => {
				warning (@"Error while deleting scheduled status: $code $message");
				app.toast (message, 0);
			})
			.exec ();
	}

	private void on_activated () {
		if (!_draft || status_widget == null) return;

		new Dialogs.Composer.Dialog.from_scheduled (bound_scheduled_status, true, status_poll, on_draft_posted);
	}

	private void on_draft_posted (API.Status x) {
		if (_draft) delete_status ();
	}

	private void on_edit () {
		new Dialogs.Composer.Dialog.from_scheduled (bound_scheduled_status, false, status_poll, on_edited);
	}

	private void on_edited (API.Status x) {
		refresh ();
	}
}
