// This file was generated with `cornucopia`. Do not modify.

#[derive(Debug)]
pub struct InsertUserParams<T1: crate::StringSql, T2: crate::StringSql> {
    pub name: T1,
    pub email: T2,
}
#[derive(Debug, Clone, PartialEq)]
pub struct GetUser {
    pub id: uuid::Uuid,
    pub name: String,
    pub email: String,
    pub created_at: chrono::DateTime<chrono::FixedOffset>,
}
pub struct GetUserBorrowed<'a> {
    pub id: uuid::Uuid,
    pub name: &'a str,
    pub email: &'a str,
    pub created_at: chrono::DateTime<chrono::FixedOffset>,
}
impl<'a> From<GetUserBorrowed<'a>> for GetUser {
    fn from(
        GetUserBorrowed {
            id,
            name,
            email,
            created_at,
        }: GetUserBorrowed<'a>,
    ) -> Self {
        Self {
            id,
            name: name.into(),
            email: email.into(),
            created_at,
        }
    }
}
#[derive(Debug, Clone, PartialEq)]
pub struct ListUsers {
    pub id: uuid::Uuid,
    pub name: String,
    pub email: String,
    pub created_at: chrono::DateTime<chrono::FixedOffset>,
}
pub struct ListUsersBorrowed<'a> {
    pub id: uuid::Uuid,
    pub name: &'a str,
    pub email: &'a str,
    pub created_at: chrono::DateTime<chrono::FixedOffset>,
}
impl<'a> From<ListUsersBorrowed<'a>> for ListUsers {
    fn from(
        ListUsersBorrowed {
            id,
            name,
            email,
            created_at,
        }: ListUsersBorrowed<'a>,
    ) -> Self {
        Self {
            id,
            name: name.into(),
            email: email.into(),
            created_at,
        }
    }
}
#[derive(Debug, Clone, PartialEq)]
pub struct InsertUser {
    pub id: uuid::Uuid,
    pub name: String,
    pub email: String,
    pub created_at: chrono::DateTime<chrono::FixedOffset>,
}
pub struct InsertUserBorrowed<'a> {
    pub id: uuid::Uuid,
    pub name: &'a str,
    pub email: &'a str,
    pub created_at: chrono::DateTime<chrono::FixedOffset>,
}
impl<'a> From<InsertUserBorrowed<'a>> for InsertUser {
    fn from(
        InsertUserBorrowed {
            id,
            name,
            email,
            created_at,
        }: InsertUserBorrowed<'a>,
    ) -> Self {
        Self {
            id,
            name: name.into(),
            email: email.into(),
            created_at,
        }
    }
}
use crate::client::async_::GenericClient;
use futures::{self, StreamExt, TryStreamExt};
pub struct GetUserQuery<'c, 'a, 's, C: GenericClient, T, const N: usize> {
    client: &'c C,
    params: [&'a (dyn postgres_types::ToSql + Sync); N],
    query: &'static str,
    cached: Option<&'s tokio_postgres::Statement>,
    extractor: fn(&tokio_postgres::Row) -> Result<GetUserBorrowed, tokio_postgres::Error>,
    mapper: fn(GetUserBorrowed) -> T,
}
impl<'c, 'a, 's, C, T: 'c, const N: usize> GetUserQuery<'c, 'a, 's, C, T, N>
where
    C: GenericClient,
{
    pub fn map<R>(self, mapper: fn(GetUserBorrowed) -> R) -> GetUserQuery<'c, 'a, 's, C, R, N> {
        GetUserQuery {
            client: self.client,
            params: self.params,
            query: self.query,
            cached: self.cached,
            extractor: self.extractor,
            mapper,
        }
    }
    pub async fn one(self) -> Result<T, tokio_postgres::Error> {
        let row =
            crate::client::async_::one(self.client, self.query, &self.params, self.cached).await?;
        Ok((self.mapper)((self.extractor)(&row)?))
    }
    pub async fn all(self) -> Result<Vec<T>, tokio_postgres::Error> {
        self.iter().await?.try_collect().await
    }
    pub async fn opt(self) -> Result<Option<T>, tokio_postgres::Error> {
        let opt_row =
            crate::client::async_::opt(self.client, self.query, &self.params, self.cached).await?;
        Ok(opt_row
            .map(|row| {
                let extracted = (self.extractor)(&row)?;
                Ok((self.mapper)(extracted))
            })
            .transpose()?)
    }
    pub async fn iter(
        self,
    ) -> Result<
        impl futures::Stream<Item = Result<T, tokio_postgres::Error>> + 'c,
        tokio_postgres::Error,
    > {
        let stream = crate::client::async_::raw(
            self.client,
            self.query,
            crate::slice_iter(&self.params),
            self.cached,
        )
        .await?;
        let mapped = stream
            .map(move |res| {
                res.and_then(|row| {
                    let extracted = (self.extractor)(&row)?;
                    Ok((self.mapper)(extracted))
                })
            })
            .into_stream();
        Ok(mapped)
    }
}
pub struct ListUsersQuery<'c, 'a, 's, C: GenericClient, T, const N: usize> {
    client: &'c C,
    params: [&'a (dyn postgres_types::ToSql + Sync); N],
    query: &'static str,
    cached: Option<&'s tokio_postgres::Statement>,
    extractor: fn(&tokio_postgres::Row) -> Result<ListUsersBorrowed, tokio_postgres::Error>,
    mapper: fn(ListUsersBorrowed) -> T,
}
impl<'c, 'a, 's, C, T: 'c, const N: usize> ListUsersQuery<'c, 'a, 's, C, T, N>
where
    C: GenericClient,
{
    pub fn map<R>(self, mapper: fn(ListUsersBorrowed) -> R) -> ListUsersQuery<'c, 'a, 's, C, R, N> {
        ListUsersQuery {
            client: self.client,
            params: self.params,
            query: self.query,
            cached: self.cached,
            extractor: self.extractor,
            mapper,
        }
    }
    pub async fn one(self) -> Result<T, tokio_postgres::Error> {
        let row =
            crate::client::async_::one(self.client, self.query, &self.params, self.cached).await?;
        Ok((self.mapper)((self.extractor)(&row)?))
    }
    pub async fn all(self) -> Result<Vec<T>, tokio_postgres::Error> {
        self.iter().await?.try_collect().await
    }
    pub async fn opt(self) -> Result<Option<T>, tokio_postgres::Error> {
        let opt_row =
            crate::client::async_::opt(self.client, self.query, &self.params, self.cached).await?;
        Ok(opt_row
            .map(|row| {
                let extracted = (self.extractor)(&row)?;
                Ok((self.mapper)(extracted))
            })
            .transpose()?)
    }
    pub async fn iter(
        self,
    ) -> Result<
        impl futures::Stream<Item = Result<T, tokio_postgres::Error>> + 'c,
        tokio_postgres::Error,
    > {
        let stream = crate::client::async_::raw(
            self.client,
            self.query,
            crate::slice_iter(&self.params),
            self.cached,
        )
        .await?;
        let mapped = stream
            .map(move |res| {
                res.and_then(|row| {
                    let extracted = (self.extractor)(&row)?;
                    Ok((self.mapper)(extracted))
                })
            })
            .into_stream();
        Ok(mapped)
    }
}
pub struct InsertUserQuery<'c, 'a, 's, C: GenericClient, T, const N: usize> {
    client: &'c C,
    params: [&'a (dyn postgres_types::ToSql + Sync); N],
    query: &'static str,
    cached: Option<&'s tokio_postgres::Statement>,
    extractor: fn(&tokio_postgres::Row) -> Result<InsertUserBorrowed, tokio_postgres::Error>,
    mapper: fn(InsertUserBorrowed) -> T,
}
impl<'c, 'a, 's, C, T: 'c, const N: usize> InsertUserQuery<'c, 'a, 's, C, T, N>
where
    C: GenericClient,
{
    pub fn map<R>(
        self,
        mapper: fn(InsertUserBorrowed) -> R,
    ) -> InsertUserQuery<'c, 'a, 's, C, R, N> {
        InsertUserQuery {
            client: self.client,
            params: self.params,
            query: self.query,
            cached: self.cached,
            extractor: self.extractor,
            mapper,
        }
    }
    pub async fn one(self) -> Result<T, tokio_postgres::Error> {
        let row =
            crate::client::async_::one(self.client, self.query, &self.params, self.cached).await?;
        Ok((self.mapper)((self.extractor)(&row)?))
    }
    pub async fn all(self) -> Result<Vec<T>, tokio_postgres::Error> {
        self.iter().await?.try_collect().await
    }
    pub async fn opt(self) -> Result<Option<T>, tokio_postgres::Error> {
        let opt_row =
            crate::client::async_::opt(self.client, self.query, &self.params, self.cached).await?;
        Ok(opt_row
            .map(|row| {
                let extracted = (self.extractor)(&row)?;
                Ok((self.mapper)(extracted))
            })
            .transpose()?)
    }
    pub async fn iter(
        self,
    ) -> Result<
        impl futures::Stream<Item = Result<T, tokio_postgres::Error>> + 'c,
        tokio_postgres::Error,
    > {
        let stream = crate::client::async_::raw(
            self.client,
            self.query,
            crate::slice_iter(&self.params),
            self.cached,
        )
        .await?;
        let mapped = stream
            .map(move |res| {
                res.and_then(|row| {
                    let extracted = (self.extractor)(&row)?;
                    Ok((self.mapper)(extracted))
                })
            })
            .into_stream();
        Ok(mapped)
    }
}
pub struct UuidUuidQuery<'c, 'a, 's, C: GenericClient, T, const N: usize> {
    client: &'c C,
    params: [&'a (dyn postgres_types::ToSql + Sync); N],
    query: &'static str,
    cached: Option<&'s tokio_postgres::Statement>,
    extractor: fn(&tokio_postgres::Row) -> Result<uuid::Uuid, tokio_postgres::Error>,
    mapper: fn(uuid::Uuid) -> T,
}
impl<'c, 'a, 's, C, T: 'c, const N: usize> UuidUuidQuery<'c, 'a, 's, C, T, N>
where
    C: GenericClient,
{
    pub fn map<R>(self, mapper: fn(uuid::Uuid) -> R) -> UuidUuidQuery<'c, 'a, 's, C, R, N> {
        UuidUuidQuery {
            client: self.client,
            params: self.params,
            query: self.query,
            cached: self.cached,
            extractor: self.extractor,
            mapper,
        }
    }
    pub async fn one(self) -> Result<T, tokio_postgres::Error> {
        let row =
            crate::client::async_::one(self.client, self.query, &self.params, self.cached).await?;
        Ok((self.mapper)((self.extractor)(&row)?))
    }
    pub async fn all(self) -> Result<Vec<T>, tokio_postgres::Error> {
        self.iter().await?.try_collect().await
    }
    pub async fn opt(self) -> Result<Option<T>, tokio_postgres::Error> {
        let opt_row =
            crate::client::async_::opt(self.client, self.query, &self.params, self.cached).await?;
        Ok(opt_row
            .map(|row| {
                let extracted = (self.extractor)(&row)?;
                Ok((self.mapper)(extracted))
            })
            .transpose()?)
    }
    pub async fn iter(
        self,
    ) -> Result<
        impl futures::Stream<Item = Result<T, tokio_postgres::Error>> + 'c,
        tokio_postgres::Error,
    > {
        let stream = crate::client::async_::raw(
            self.client,
            self.query,
            crate::slice_iter(&self.params),
            self.cached,
        )
        .await?;
        let mapped = stream
            .map(move |res| {
                res.and_then(|row| {
                    let extracted = (self.extractor)(&row)?;
                    Ok((self.mapper)(extracted))
                })
            })
            .into_stream();
        Ok(mapped)
    }
}
pub struct GetUserStmt(&'static str, Option<tokio_postgres::Statement>);
pub fn get_user() -> GetUserStmt {
    GetUserStmt(
        "SELECT id, name, email, created_at FROM users WHERE id = $1",
        None,
    )
}
impl GetUserStmt {
    pub async fn prepare<'a, C: GenericClient>(
        mut self,
        client: &'a C,
    ) -> Result<Self, tokio_postgres::Error> {
        self.1 = Some(client.prepare(self.0).await?);
        Ok(self)
    }
    pub fn bind<'c, 'a, 's, C: GenericClient>(
        &'s self,
        client: &'c C,
        id: &'a uuid::Uuid,
    ) -> GetUserQuery<'c, 'a, 's, C, GetUser, 1> {
        GetUserQuery {
            client,
            params: [id],
            query: self.0,
            cached: self.1.as_ref(),
            extractor:
                |row: &tokio_postgres::Row| -> Result<GetUserBorrowed, tokio_postgres::Error> {
                    Ok(GetUserBorrowed {
                        id: row.try_get(0)?,
                        name: row.try_get(1)?,
                        email: row.try_get(2)?,
                        created_at: row.try_get(3)?,
                    })
                },
            mapper: |it| GetUser::from(it),
        }
    }
}
pub struct ListUsersStmt(&'static str, Option<tokio_postgres::Statement>);
pub fn list_users() -> ListUsersStmt {
    ListUsersStmt(
        "SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT 100",
        None,
    )
}
impl ListUsersStmt {
    pub async fn prepare<'a, C: GenericClient>(
        mut self,
        client: &'a C,
    ) -> Result<Self, tokio_postgres::Error> {
        self.1 = Some(client.prepare(self.0).await?);
        Ok(self)
    }
    pub fn bind<'c, 'a, 's, C: GenericClient>(
        &'s self,
        client: &'c C,
    ) -> ListUsersQuery<'c, 'a, 's, C, ListUsers, 0> {
        ListUsersQuery {
            client,
            params: [],
            query: self.0,
            cached: self.1.as_ref(),
            extractor:
                |row: &tokio_postgres::Row| -> Result<ListUsersBorrowed, tokio_postgres::Error> {
                    Ok(ListUsersBorrowed {
                        id: row.try_get(0)?,
                        name: row.try_get(1)?,
                        email: row.try_get(2)?,
                        created_at: row.try_get(3)?,
                    })
                },
            mapper: |it| ListUsers::from(it),
        }
    }
}
pub struct InsertUserStmt(&'static str, Option<tokio_postgres::Statement>);
pub fn insert_user() -> InsertUserStmt {
    InsertUserStmt(
        "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at",
        None,
    )
}
impl InsertUserStmt {
    pub async fn prepare<'a, C: GenericClient>(
        mut self,
        client: &'a C,
    ) -> Result<Self, tokio_postgres::Error> {
        self.1 = Some(client.prepare(self.0).await?);
        Ok(self)
    }
    pub fn bind<'c, 'a, 's, C: GenericClient, T1: crate::StringSql, T2: crate::StringSql>(
        &'s self,
        client: &'c C,
        name: &'a T1,
        email: &'a T2,
    ) -> InsertUserQuery<'c, 'a, 's, C, InsertUser, 2> {
        InsertUserQuery {
            client,
            params: [name, email],
            query: self.0,
            cached: self.1.as_ref(),
            extractor:
                |row: &tokio_postgres::Row| -> Result<InsertUserBorrowed, tokio_postgres::Error> {
                    Ok(InsertUserBorrowed {
                        id: row.try_get(0)?,
                        name: row.try_get(1)?,
                        email: row.try_get(2)?,
                        created_at: row.try_get(3)?,
                    })
                },
            mapper: |it| InsertUser::from(it),
        }
    }
}
impl<'c, 'a, 's, C: GenericClient, T1: crate::StringSql, T2: crate::StringSql>
    crate::client::async_::Params<
        'c,
        'a,
        's,
        InsertUserParams<T1, T2>,
        InsertUserQuery<'c, 'a, 's, C, InsertUser, 2>,
        C,
    > for InsertUserStmt
{
    fn params(
        &'s self,
        client: &'c C,
        params: &'a InsertUserParams<T1, T2>,
    ) -> InsertUserQuery<'c, 'a, 's, C, InsertUser, 2> {
        self.bind(client, &params.name, &params.email)
    }
}
pub struct DeleteUserStmt(&'static str, Option<tokio_postgres::Statement>);
pub fn delete_user() -> DeleteUserStmt {
    DeleteUserStmt("DELETE FROM users WHERE id = $1 RETURNING id", None)
}
impl DeleteUserStmt {
    pub async fn prepare<'a, C: GenericClient>(
        mut self,
        client: &'a C,
    ) -> Result<Self, tokio_postgres::Error> {
        self.1 = Some(client.prepare(self.0).await?);
        Ok(self)
    }
    pub fn bind<'c, 'a, 's, C: GenericClient>(
        &'s self,
        client: &'c C,
        id: &'a uuid::Uuid,
    ) -> UuidUuidQuery<'c, 'a, 's, C, uuid::Uuid, 1> {
        UuidUuidQuery {
            client,
            params: [id],
            query: self.0,
            cached: self.1.as_ref(),
            extractor: |row| Ok(row.try_get(0)?),
            mapper: |it| it,
        }
    }
}
