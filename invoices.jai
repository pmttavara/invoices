#import "Basic";
#import "Curl";
#import "Compiler";
#import "File";
#import "Process";
#import "String";



makeday :: (year: s32, month: s8, day: s8) -> Calendar_Time {
    return Calendar_Time.{
        year = year,
        month_starting_at_0 = month - 1,
        day_of_month_starting_at_0 = day - 1
    };
}

#load "secrets.jai";

#load "template.html";
#load "payload.json";

write_callback :: (contents: *u8, count: u64, size: u64, file: *File) -> u64 #c_call {
    total_size := count * size;
    push_context,defer_pop;

    file_write(file, contents, cast(s64, total_size));

    print("Wrote % bytes: \"%\".\n\n\n", total_size, string.{cast(s64, total_size), contents});

    return total_size;
}

fetch_toggl_csv :: () {
    out_file, ok := file_open("time_entries.csv", for_writing=true);
    assert(ok);
    defer {
        file_flush(*out_file);
        file_close(*out_file);
    }

    if 0 {
        curl := curl_easy_init();
        defer curl_easy_cleanup(curl);
        assert(curl != null);

        curl_easy_setopt(curl, .VERBOSE, 1);
        curl_easy_setopt(curl, .URL, "https://api.track.toggl.com/api/v9/me");
        curl_easy_setopt(curl, .USERNAME, toggl_username);
        curl_easy_setopt(curl, .PASSWORD, toggl_password);

        curl_easy_setopt(curl, .USE_SSL, curl_usessl.ALL);
        curl_easy_setopt(curl, .SSL_VERIFYPEER, 0);
        curl_easy_setopt(curl, .SSL_VERIFYHOST, 0);


        res := curl_easy_perform(curl);
        return;
    }

    curl := curl_easy_init();
    defer curl_easy_cleanup(curl);
    assert(curl != null);

    curl_easy_setopt(curl, .VERBOSE, 1);
    // curl_easy_setopt(curl, .URL, "https://api.track.toggl.com/api/v9/me");
    curl_easy_setopt(curl, .USERNAME, toggl_username);
    curl_easy_setopt(curl, .PASSWORD, toggl_password);

    // payload: String_Builder;

    curl_easy_setopt(curl, .URL, toggl_time_entries_string);
    curl_easy_setopt(curl, .POST, 1);

    curl_easy_setopt(curl, .WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, .WRITEDATA, *out_file);

    Upload_Context :: struct {
        payload : string;
    }
    payload_source :: (ptr : *s8, size : s64, nmemb : s64, userp : *void) -> s64 #c_call {
        push_context,defer_pop;

        assert(ptr != null);
        assert(userp != null);

        if (size == 0) || (nmemb == 0) || ((size*nmemb) <= 1) then {
            return 0;
        }

        ctx := cast(*Upload_Context) userp;

        if ctx.payload == "" {
            return 0;
        }

        count := min(size * nmemb, ctx.payload.count);
        memcpy(ptr, ctx.payload.data, count);  // @Cleanup: Will be an intrinsic.
        ctx.payload = slice(ctx.payload, count, ctx.payload.count-count);

        return count;
    }

    ctx := Upload_Context.{ payload };
    curl_easy_setopt(curl, .READDATA, *ctx);
    curl_easy_setopt(curl, .UPLOAD, 1);
    curl_easy_setopt(curl, .READFUNCTION, payload_source);

    curl_easy_setopt(curl, .USE_SSL, curl_usessl.ALL);
    curl_easy_setopt(curl, .SSL_VERIFYPEER, 0);
    curl_easy_setopt(curl, .SSL_VERIFYHOST, 0);


    res := curl_easy_perform(curl);
    assert(res == .OK, "curl_easy_perform() failed: %\n", to_string(curl_easy_strerror(res)));
}




main :: () {
    // fetch_toggl_csv();

    entries, file_open_ok := file_open("time_entries.csv");
    assert(file_open_ok);

    invoice_date := to_calendar(current_time_consensus(), Time_Zone.LOCAL);

    // start_date := to_calendar(current_time_consensus(), Time_Zone.UTC);
    // end_date   := to_calendar(current_time_consensus(), Time_Zone.UTC);

//     extra_invoice_content :: #string END
// END;
//     formatted_extra_invoice_content := split(extra_invoice_content, "\n");


    total_price := hours_count * hourly_rate;


    invoice_year := invoice_date.year;
    invoice_month := invoice_date.month_starting_at_0 + 1;
    invoice_day := invoice_date.day_of_month_starting_at_0 + 1;
    invoice_number_string := FormatInt.{value = invoice_number, minimum_digits = 4};

    months :: string.["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

    start_year := start_date.year;
    start_month := months[start_date.month_starting_at_0];
    start_day := start_date.day_of_month_starting_at_0 + 1;

    end_year := end_date.year;
    end_month := months[end_date.month_starting_at_0];
    end_day := end_date.day_of_month_starting_at_0 + 1;

    Variable :: struct {
        key: string;
        value: Any;
    };
    variables : [] Variable = .[
        .{"my_name",               my_name},
        .{"my_addr",               my_addr},
        .{"my_city",               my_city},
        .{"my_post",               my_post},
        .{"invoice_year",          invoice_year},
        .{"invoice_month",         invoice_month},
        .{"invoice_day",           invoice_day},
        .{"invoice_number_string", invoice_number_string},
        .{"company",               company},
        .{"street_address",        street_address},
        .{"city",                  city},
        .{"postal_code",           postal_code},
        .{"business_number",       business_number},
        .{"hours_count",           hours_count},
        .{"start_month",           start_month},
        .{"start_day",             start_day},
        .{"start_year",            start_year},
        .{"end_month",             end_month},
        .{"end_day",               end_day},
        .{"end_year",              end_year},
        .{"total_price",           total_price},
    ];

    builder: String_Builder;
    split_by_variable := split(template, "$");
    for key: split_by_variable {
        for variables {
            if key == it.key {
                print_to_builder(*builder, "%", it.value);
                continue key;
            }
        }

        print_to_builder(*builder, "%", key);
    }

    filename := tprint("% - Invoice % - % - Development - % % to % %",
                       my_name, invoice_number_string, company, start_month, start_day, end_month, end_day);
    file_html := tprint("%.html", filename);
    file_pdf  := tprint("%.pdf", filename);
    write_entire_file(file_html, *builder, true);
    result := run_command("wkhtmltopdf", file_html, file_pdf);
    if result.type == .EXITED && result.exit_code == 0 {
        print("Success!");
        file_delete(file_html);
    }
}
