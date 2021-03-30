module builder

import os
import v.parser
import v.pref
import v.util
import v.gen.c
import v.markused

pub fn (mut b Builder) gen_c(v_files []string) string {
	util.timing_start('PARSE')
	b.parsed_files = parser.parse_files(v_files, b.table, b.pref, b.global_scope)
	b.parse_imports()
	util.get_timers().show('SCAN')
	util.get_timers().show('PARSE')
	util.get_timers().show_if_exists('PARSE stmt')
	if b.pref.only_check_syntax {
		return ''
	}

	util.timing_start('CHECK')
	b.table.generic_struct_insts_to_concrete()
	b.checker.check_files(b.parsed_files)
	util.timing_measure('CHECK')

	if b.pref.skip_unused {
		markused.mark_used(mut b.table, b.pref, b.parsed_files)
	}

	b.print_warnings_and_errors()
	// TODO: move gen.cgen() to c.gen()
	util.timing_start('C GEN')
	res := c.gen(b.parsed_files, b.table, b.pref)
	util.timing_measure('C GEN')
	// println('cgen done')
	// println(res)
	return res
}

pub fn (mut b Builder) build_c(v_files []string, out_file string) {
	b.out_name_c = out_file
	b.pref.out_name_c = os.real_path(out_file)
	b.info('build_c($out_file)')
	output2 := b.gen_c(v_files)
	mut f := os.create(out_file) or { panic(err) }
	f.writeln(output2) or { panic(err) }
	f.close()
	if b.pref.is_stats {
		slines := util.bold((output2.count('\n') + 1).str())
		sbytes := util.bold(output2.len.str())
		println('generated C source code size: $slines lines, $sbytes bytes')
	}
	// os.write_file(out_file, b.gen_c(v_files))
}

pub fn (mut b Builder) compile_c() {
	if os.user_os() != 'windows' && b.pref.ccompiler == 'msvc' && !b.pref.out_name.ends_with('.c') {
		verror('Cannot build with msvc on $os.user_os()')
	}
	// cgen.genln('// Generated by V')
	// println('compile2()')
	if b.pref.is_verbose {
		println('all .v files before:')
		// println(files)
	}
	$if windows {
		b.find_win_cc() or { verror(no_compiler_error) }
		// TODO Probably extend this to other OS's?
	}
	// v1 compiler files
	// v.add_v_files_to_compile()
	// v.files << v.dir
	// v2 compiler
	// b.set_module_lookup_paths()
	mut files := b.get_builtin_files()
	files << b.get_user_files()
	b.set_module_lookup_paths()
	if b.pref.is_verbose {
		println('all .v files:')
		println(files)
	}
	mut out_name_c := b.get_vtmp_filename(b.pref.out_name, '.tmp.c')
	if b.pref.is_shared {
		out_name_c = b.get_vtmp_filename(b.pref.out_name, '.tmp.so.c')
	}
	b.build_c(files, out_name_c)
	b.cc()
}
