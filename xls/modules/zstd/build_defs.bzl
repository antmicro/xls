def _collect_textproto_reports_impl(ctx):
    textproto_reports = []
    for src in ctx.attr.srcs:
        for file in src[DefaultInfo].files.to_list():
            if file.basename.endswith("_report.textproto"):
                textproto_reports.append(file)

    return [
        DefaultInfo(
            files = depset(textproto_reports),
            runfiles = ctx.runfiles(transitive_files = depset(textproto_reports)),
        ),
    ]

collect_textproto_reports = rule(
    implementation = _collect_textproto_reports_impl,
    attrs = {
        "srcs": attr.label_list(providers = [DefaultInfo]),
    },
)
