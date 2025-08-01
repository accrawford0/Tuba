public class Tuba.Widgets.StatusActionButton : Gtk.Button {
	public Adw.ButtonContent content { get; set; }

	private string _default_icon_name = "";
	public string default_icon_name {
		get {
			return _default_icon_name;
		}

		set {
			_default_icon_name = value;
			update_button_style ();
		}
	}

	public string? active_icon_name { get; construct set; default = null; }
	public bool working { get; private set; default = false; }

	private int64 _amount = 0;
	public int64 amount {
		get { return _amount; }
		set {
			_amount = value;
			update_button_content (value);
			//  update_aria_label ();
		}
	}

	private bool _active = false;
	public bool active {
		get {
			return _active;
		}

		set {
			_active = value;
			update_button_style (value);
		}
	}

	//  private void update_aria_label () {
	//  	if (this.tooltip_text == null) return;

	//  	this.update_property (
	//  		Gtk.AccessibleProperty.DESCRIPTION,
	//  		" ",
	//  		-1
	//  	);

	//  	this.update_property (
	//  		Gtk.AccessibleProperty.LABEL,
	//  		@"$(this.tooltip_text) ($_amount)",
	//  		-1
	//  	);
	//  }

	private void update_button_style (bool value = active) {
		if (value) {
			remove_css_class ("flat");
			add_css_class ("enabled");
			content.icon_name = active_icon_name ?? default_icon_name;
			this.update_state (Gtk.AccessibleState.PRESSED, Gtk.AccessibleTristate.TRUE, -1);
		} else {
			add_css_class ("flat");
			remove_css_class ("enabled");
			content.icon_name = default_icon_name;
			this.update_state (Gtk.AccessibleState.PRESSED, Gtk.AccessibleTristate.FALSE, -1);
		}
	}

	private void update_button_content (int64 new_value) {
		if (new_value == 0) {
			content.label = "";
			content.margin_start = 0;
			content.margin_end = 0;

			return;
		}

		content.label = Utils.Units.shorten (new_value);
		content.margin_start = 12;
		content.margin_end = 9;
	}

	public void block_clicked () {
		working = true;
	}

	public void unblock_clicked () {
		working = false;
	}

	static construct {
		set_accessible_role (Gtk.AccessibleRole.TOGGLE_BUTTON);
	}

	construct {
		content = new Adw.ButtonContent ();
		this.child = content;
		//  update_aria_label ();

		//  this.notify["tooltip-text"].connect (update_aria_label);
	}

	public StatusActionButton.with_icon_name (string icon_name) {
		Object (
			default_icon_name: icon_name
		);
	}
}
