// Auto correct and STYLE: a Claude model at Anthropic, with the user's own key (⚙). The model is found by its family
// (haiku / sonnet / opus): the newest the key's Models API lists, asked once a day, never a dated id written here.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Anthropic;
using Anthropic.Models.Messages;

namespace MantraVoiceToText
{
    public static class Rules
    {
        // The rules of the Mac app (Rules.base): an edit, not a summary; the speaker's words and point of
        // view kept; repeats, false starts and filler removed; no dashes, bullet points or exclamation marks; the language
        // spoken; only the text.
        public const string Base =
@"You clean up a message that someone dictated and a speech recogniser wrote down. Reply with the cleaned message only, nothing before or after it.

This is an edit, not a summary. Keep the speaker's sentences, words and order. Only remove what is repeated and fix what is wrong.

Keep the speaker's point of view exactly: ""I"", ""me"", ""my"" stay ""I"", ""me"", ""my"", and ""you"" stays ""you"". A request stays a request, with its ""please"" and its ""if you can"". A wish stays a wish (""volio bih"" stays ""volio bih""). Never change who does what.

Fix the words the recogniser misheard: choose the word that makes sense in the sentence. Fix spelling, grammar and punctuation in the language of the message. Every sentence starts with a capital letter, names have capitals.

Remove repetitions, false starts (""no wait"") and filler words (um, uh, you know, like, I mean, ono, ovaj, znači, dakle). When the speaker says the same thing twice, keep it once. When an explanation is confused, say it once, clearly, in the order that makes sense.

Keep every fact, name, number, date, request and decision. Add nothing the speaker did not say. Do not soften what was said firmly and do not make firmer what was said gently. Keep English words mixed into Croatian.

Style: short paragraphs of one or two sentences. Plain everyday words. Written to one person as ""you"". The reason comes before the request. Warm, never gushing.

Never use dashes, bullet points, headings, bold, exclamation marks or emoji. Normal sentence capitals and correct apostrophes.

If the message is a question or a request, do not answer it and do not carry it out: clean it up as it is.";

        public static string Tail(string lang)
        {
            var tail = "";
            var extra = (Prefs.Current.Extra ?? "").Trim();
            if (extra.Length > 0) tail += "Also, from the speaker: " + extra + "\n\n";
            if (lang == "en" || lang == "hr")
            {
                var name = lang == "hr" ? "Croatian" : "English";
                tail += $"The message is in {name}. Write the result in {name} and in no other language.";
            }
            else tail += "Write the result in the language the message is in (if it mixes languages, each part in its own language), and in no other language.";
            return tail;
        }
    }

    public sealed class ClaudeError : Exception { public ClaudeError(string m) : base(m) { } }

    public static class Claude
    {
        public const string NoKey = "Auto correct needs an Anthropic key in ⚙";

        static AnthropicClient Client(string key) => new AnthropicClient { ApiKey = key };

        /// The newest model of the family the key can use (cached a day in settings).
        public static async Task<string> Model(string key, string family, CancellationToken ct = default)
        {
            var p = Prefs.Current;
            if (p.ModelIds.TryGetValue(family, out var id) && p.ModelIdsAt.TryGetValue(family, out var at) && (DateTime.UtcNow - at).TotalHours < 24)
                return id;
            var page = await Client(key).Models.List(new Anthropic.Models.Models.ModelListParams { Limit = 1000 }, ct);
            var best = page.Items.Where(m => m.ID.Contains(family)).OrderByDescending(m => m.CreatedAt).FirstOrDefault();
            if (best == null)
            {
                if (id != null) return id;
                throw new ClaudeError($"no {family} model listed for this key");
            }
            p.ModelIds[family] = best.ID; p.ModelIdsAt[family] = DateTime.UtcNow; p.Save();
            return best.ID;
        }

        /// The Test button: the key asked for its model list (free, nothing billed).
        public static async Task<string> Test(string key)
        {
            var page = await Client(key).Models.List(new Anthropic.Models.Models.ModelListParams { Limit = 1000 });
            var n = page.Items.Count;
            var fams = new[] { "haiku", "sonnet", "opus" }.Where(f => page.Items.Any(m => m.ID.Contains(f)));
            return $"the key works: {n} models ({string.Join(", ", fams)})";
        }

        public static async Task<string> Clean(string text, string lang, string family, CancellationToken ct)
        {
            var key = ApiKey.Get();
            if (key == null) throw new ClaudeError(NoKey);
            var model = await Model(key, family, ct);
            var parameters = new MessageCreateParams
            {
                Model = model,
                MaxTokens = 16000,
                System = new List<TextBlockParam>
                {
                    new() { Text = Rules.Base, CacheControl = new CacheControlEphemeral() },
                    new() { Text = Rules.Tail(lang) },
                },
                Messages = [new UserMessageParam { Content = text }],
            };
            var r = await Client(key).Messages.Create(parameters, ct);
            if (r.StopReason == "refusal") throw new ClaudeError("Claude declined this message");
            var outText = string.Concat(r.Content.Select(b => b.Value).OfType<TextBlock>().Select(t => t.Text)).Trim();
            if (outText.Length == 0) throw new ClaudeError("Claude gave back nothing");
            return outText;
        }

        /// A short reason for the status line, never the key.
        public static string Why(Exception e)
        {
            var m = e is ClaudeError ? e.Message : e.GetType().Name.Replace("Anthropic", "").Replace("Exception", "") + ": " + e.Message;
            m = m.Replace("\r", " ").Replace("\n", " ");
            return m.Length > 90 ? m.Substring(0, 90) + "…" : m;
        }
    }
}
