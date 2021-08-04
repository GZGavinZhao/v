module cli

pub struct Option {
pub:
	abbrev string
	aliases []string
	allowed []string // Define allowed options
	allowed_help map[string]string
	default_value string
	description string [required]
	hide bool // Note: struct fields are zeroed (false) by default
	mandatory bool
	multi bool // Whether this option allow multiple values
	name string [requierd]
}