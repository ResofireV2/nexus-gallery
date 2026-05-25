![Nexus Gallery](https://raw.githubusercontent.com/ResofireV2/nexus-gallery/main/priv/static/banner.webp)

# Nexus Gallery

A community media gallery extension for [Nexus](https://github.com/billyrayfoss/nexus). Supports image and video uploads, YouTube embeds, collections, ratings, comments, reactions, subscriptions, a Following feed tab, automatic image harvesting from forum posts, a moderation queue, and an admin stats dashboard.

## Features

- **Browse** — paginated grid with sort, tag filtering, and search across images, videos, and embeds
- **Upload** — drag-and-drop multi-file uploader with live progress, client-side video thumbnail generation
- **Detail page** — hero display, 5-star ratings, emoji reactions, comments (markdown), tags, follow button
- **Collections** — create named collections, add items, follow collections
- **Tags** — admin-managed tags with colour coding; follow tags for activity updates
- **Subscriptions** — follow individual items, collections, and tags; activity appears in the Nexus Following feed
- **Notifications** — in-app notifications for ratings, comments, and new images on followed tags/collections
- **Harvest** — automatically import images from forum posts into the gallery by mapping spaces to gallery tags
- **Moderation queue** — optional approval step before uploads appear publicly
- **Admin panel** — settings, tag management, harvest mapping, moderation queue, and stats dashboard
- **Profile tab** — gallery uploads tab on Nexus user profiles
- **Right widgets** — gallery stats, top rated, tags, and top uploaders sidebar widgets

## Requirements

- Nexus `manifest_version` 2
- Elixir 1.17+

## Installation

In the Nexus admin panel go to **Admin → Extensions → Install**, then paste the repository URL:

```
https://github.com/ResofireV2/nexus-gallery
```

## Configuration

After installation, open **Admin → Extensions → Gallery → Manage** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Ratings enabled | Off | Allow members to rate gallery items |
| Reactions enabled | Off | Allow emoji reactions on items |
| Comments enabled | Off | Allow comments on items and collections |
| Video uploads enabled | Off | Allow MP4/WebM video uploads |
| Embeds enabled | On | Allow YouTube embed submissions |
| Moderation queue | Off | Require admin approval before uploads go public |
| Block self-ratings | Off | Prevent users from rating their own items |
| Max tags per item | 5 | Maximum number of tags per gallery item |

### Harvest

Map Nexus spaces to gallery tags under the **Harvest** tab. When a post containing an uploaded image is made in a mapped space, the image is automatically imported into the linked gallery tag.

## License

MIT
